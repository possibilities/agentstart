#!/usr/bin/env bun

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { defaultProjectRoots, inspectCandidate, inspectWorktree, normalizePath } from "./git.ts";

type AgentStatus = "idle" | "working" | "blocked" | "done" | "unknown";
type RecordValue = Record<string, unknown>;

export interface CandidateTrigger {
  agent: RecordValue;
  reason: "startup" | "transition";
}

export interface ReapTrigger {
  workspace_id: string;
  workspace: RecordValue | null;
  agents: RecordValue[];
}

interface TrackedAgent {
  status: AgentStatus;
  row: RecordValue;
}

interface WatchOptions {
  socketPath: string;
  projectRoots: string[];
  selfPaneId: string | null;
  wakeSelf: boolean;
  once: boolean;
}

const SUBSCRIPTIONS = [
  { type: "pane.created" },
  { type: "pane.updated" },
  { type: "pane.closed" },
  { type: "pane.exited" },
  { type: "pane.agent_detected" },
  { type: "workspace.closed" },
];

function asRecord(value: unknown): RecordValue | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as RecordValue)
    : null;
}

function asStatus(value: unknown): AgentStatus {
  return value === "idle" || value === "working" || value === "blocked" || value === "done"
    ? value
    : "unknown";
}

function paneId(row: RecordValue): string | null {
  return typeof row["pane_id"] === "string" ? row["pane_id"] : null;
}

function stopped(status: AgentStatus): boolean {
  return status === "idle" || status === "done";
}

export class AgentTracker {
  private readonly agents = new Map<string, TrackedAgent>();

  handleEvent(event: string, data: RecordValue): CandidateTrigger[] {
    switch (event) {
      case "pane_created":
      case "pane_updated": {
        const pane = asRecord(data["pane"]);
        return pane ? this.observe(pane, false) : [];
      }
      case "pane_closed":
      case "pane_exited": {
        const id = paneId(data);
        if (id) this.agents.delete(id);
        return [];
      }
      case "pane_agent_detected": {
        if (data["released"] === true) {
          const id = paneId(data);
          if (id) this.agents.delete(id);
        }
        return [];
      }
      default:
        return [];
    }
  }

  reconcile(rows: readonly RecordValue[]): CandidateTrigger[] {
    const triggers: CandidateTrigger[] = [];
    const seen = new Set<string>();
    for (const row of rows) {
      const id = paneId(row);
      if (!id) continue;
      seen.add(id);
      triggers.push(...this.observe(row, true));
    }
    for (const id of this.agents.keys()) {
      if (!seen.has(id)) this.agents.delete(id);
    }
    return triggers;
  }

  private observe(row: RecordValue, fromReconcile: boolean): CandidateTrigger[] {
    const id = paneId(row);
    if (!id) return [];
    const next = asStatus(row["agent_status"]);
    const tracked = this.agents.get(id);
    if (!tracked) {
      this.agents.set(id, { status: next, row });
      return fromReconcile && stopped(next) ? [{ agent: row, reason: "startup" }] : [];
    }

    const previous = tracked.status;
    tracked.row = { ...tracked.row, ...row };
    if (next !== "unknown") tracked.status = next;
    return previous === "working" && stopped(next)
      ? [{ agent: tracked.row, reason: "transition" }]
      : [];
  }
}

interface ReapWorkspaceState {
  agents: Map<string, RecordValue>;
  exited: Set<string>;
  closed: RecordValue | null | undefined;
  emitted: boolean;
}

export class ReapTracker {
  private readonly panes = new Map<string, RecordValue>();
  private readonly workspaces = new Map<string, ReapWorkspaceState>();

  handleEvent(event: string, data: RecordValue): ReapTrigger[] {
    switch (event) {
      case "pane_created":
      case "pane_updated": {
        const pane = asRecord(data["pane"]);
        if (pane) this.observe(pane);
        return [];
      }
      case "pane_closed":
      case "pane_exited":
        return this.markExited(paneId(data));
      case "pane_agent_detected":
        return data["released"] === true ? this.markExited(paneId(data)) : [];
      case "workspace_closed":
        return this.closeWorkspace(data);
      default:
        return [];
    }
  }

  reconcile(rows: readonly RecordValue[]): ReapTrigger[] {
    const seen = new Set<string>();
    const triggers: ReapTrigger[] = [];
    for (const row of rows) {
      const id = paneId(row);
      if (!id) continue;
      seen.add(id);
      this.observe(row);
    }
    for (const id of this.panes.keys()) {
      if (!seen.has(id)) triggers.push(...this.markExited(id));
    }
    return triggers;
  }

  private observe(row: RecordValue): void {
    const id = paneId(row);
    const workspaceId = typeof row["workspace_id"] === "string" ? row["workspace_id"] : null;
    if (!id || !workspaceId) return;
    const previous = this.panes.get(id) ?? {};
    const merged = { ...previous, ...row };
    this.panes.set(id, merged);
    const state = this.state(workspaceId);
    state.agents.set(id, merged);
  }

  private markExited(id: string | null): ReapTrigger[] {
    if (!id) return [];
    const row = this.panes.get(id);
    const workspaceId = row && typeof row["workspace_id"] === "string" ? row["workspace_id"] : null;
    if (!workspaceId) return [];
    const state = this.state(workspaceId);
    state.exited.add(id);
    return this.maybeEmit(workspaceId, state);
  }

  private closeWorkspace(data: RecordValue): ReapTrigger[] {
    const workspaceId = typeof data["workspace_id"] === "string" ? data["workspace_id"] : null;
    if (!workspaceId) return [];
    const state = this.state(workspaceId);
    state.closed = asRecord(data["workspace"]);
    // Closing a workspace terminates every pane it contained. Pane exit/release
    // events normally arrive too, but the closed snapshot itself is authoritative
    // when those events race or are coalesced.
    for (const id of state.agents.keys()) state.exited.add(id);
    return this.maybeEmit(workspaceId, state);
  }

  private maybeEmit(workspaceId: string, state: ReapWorkspaceState): ReapTrigger[] {
    if (state.emitted || state.closed === undefined || state.agents.size === 0) return [];
    if ([...state.agents.keys()].some((id) => !state.exited.has(id))) return [];
    state.emitted = true;
    return [{ workspace_id: workspaceId, workspace: state.closed, agents: [...state.agents.values()] }];
  }

  private state(workspaceId: string): ReapWorkspaceState {
    let state = this.workspaces.get(workspaceId);
    if (!state) {
      state = { agents: new Map(), exited: new Set(), closed: undefined, emitted: false };
      this.workspaces.set(workspaceId, state);
    }
    return state;
  }
}

export function candidateFromTrigger(
  trigger: CandidateTrigger,
  roots: readonly string[],
  selfPaneId: string | null,
): RecordValue | null {
  const agent = trigger.agent;
  const id = paneId(agent);
  if (!id || id === selfPaneId) return null;

  const declaredCwd = typeof agent["cwd"] === "string" ? agent["cwd"] : null;
  const foregroundCwd = typeof agent["foreground_cwd"] === "string" ? agent["foreground_cwd"] : null;
  let repository = declaredCwd ? inspectCandidate(declaredCwd, roots) : null;
  if (!repository && foregroundCwd && foregroundCwd !== declaredCwd) {
    repository = inspectCandidate(foregroundCwd, roots);
  }
  if (!repository) return null;

  const session = asRecord(agent["agent_session"]);
  const sessionId = session && typeof session["value"] === "string" ? session["value"] : null;
  if (!sessionId) return null;

  return {
    schema_version: 1,
    type: "merge_candidate",
    reason: trigger.reason,
    pane_id: id,
    session_id: sessionId,
    harness: session && typeof session["agent"] === "string" ? session["agent"] : null,
    cwd: declaredCwd ?? foregroundCwd,
    ...repository,
  };
}

export function reapCandidateFromTrigger(
  trigger: ReapTrigger,
  roots: readonly string[],
  selfPaneId: string | null,
): RecordValue | null {
  const workspaceWorktree = trigger.workspace ? asRecord(trigger.workspace["worktree"]) : null;
  if (workspaceWorktree?.["is_linked_worktree"] === false) return null;
  const recordedAgents = trigger.agents.filter((agent) => paneId(agent) !== selfPaneId);
  if (recordedAgents.length === 0) return null;
  const checkout =
    workspaceWorktree && typeof workspaceWorktree["checkout_path"] === "string"
      ? workspaceWorktree["checkout_path"]
      : typeof recordedAgents[0]?.["cwd"] === "string"
        ? recordedAgents[0]["cwd"]
        : null;
  if (!checkout) return null;
  const repository = inspectWorktree(checkout, roots);
  if (!repository || !repository.branch || repository.branch === "main") return null;

  const agents = recordedAgents.flatMap((agent) => {
    const session = asRecord(agent["agent_session"]);
    const sessionId = session && typeof session["value"] === "string" ? session["value"] : null;
    if (!sessionId) return [];
    return [
      {
        pane_id: paneId(agent),
        session_id: sessionId,
        harness: session && typeof session["agent"] === "string" ? session["agent"] : null,
      },
    ];
  });
  if (agents.length === 0) return null;

  return {
    schema_version: 1,
    type: "reap_candidate",
    workspace_id: trigger.workspace_id,
    agents,
    ...repository,
  };
}

class HerdrWatcher {
  private readonly options: WatchOptions;
  private readonly tracker = new AgentTracker();
  private readonly reapTracker = new ReapTracker();
  private stream: { write(data: string): number; end(): void } | null = null;
  private buffer = "";
  private queuedEvents: Array<{ event: string; data: RecordValue }> = [];
  private reconciling = false;
  private acknowledgement: { resolve(): void; reject(error: Error): void } | null = null;
  private failures = 0;
  private stopped = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private selfSessionId: string | null | undefined;

  constructor(options: WatchOptions) {
    this.options = options;
  }

  async runOnce(): Promise<void> {
    await this.connect(false);
    this.stop();
  }

  start(): void {
    void this.connect(true);
  }

  stop(): void {
    this.stopped = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = null;
    this.stream?.end();
    this.stream = null;
  }

  private async connect(reconnect: boolean): Promise<void> {
    this.buffer = "";
    this.queuedEvents = [];
    try {
      let resolveAcknowledgement: (() => void) | null = null;
      let rejectAcknowledgement: ((error: Error) => void) | null = null;
      const acknowledged = new Promise<void>((resolvePromise, rejectPromise) => {
        resolveAcknowledgement = resolvePromise;
        rejectAcknowledgement = rejectPromise;
      });
      this.acknowledgement = {
        resolve: () => resolveAcknowledgement?.(),
        reject: (error) => rejectAcknowledgement?.(error),
      };
      const socket = await Bun.connect({
        unix: this.options.socketPath,
        socket: {
          data: (_socket, chunk) => this.handleChunk(chunk),
          close: () => {
            if (this.acknowledgement) {
              const acknowledgement = this.acknowledgement;
              this.acknowledgement = null;
              acknowledgement.reject(new Error("subscription connection closed before acknowledgement"));
            }
            this.stream = null;
            if (reconnect && !this.stopped) this.scheduleReconnect();
          },
          error: (_socket, error) => {
            if (this.acknowledgement) {
              const acknowledgement = this.acknowledgement;
              this.acknowledgement = null;
              acknowledgement.reject(error);
            }
            this.diagnostic(`stream error: ${error.message}`);
          },
        },
      });
      this.stream = socket as unknown as { write(data: string): number; end(): void };
      this.stream.write(
        `${JSON.stringify({
          id: "supervisor:subscribe",
          method: "events.subscribe",
          params: { subscriptions: SUBSCRIPTIONS },
        })}\n`,
      );
      await acknowledged;
      this.failures = 0;
      const rows = await this.listAgents();
      for (const trigger of this.tracker.reconcile(rows)) await this.publishMerge(trigger);
      for (const trigger of this.reapTracker.reconcile(rows)) await this.publishReap(trigger);
      this.reconciling = false;
      const buffered = this.queuedEvents;
      this.queuedEvents = [];
      for (const event of buffered) await this.handleEvent(event.event, event.data);
    } catch (error) {
      this.diagnostic(`connection failed: ${error instanceof Error ? error.message : String(error)}`);
      this.stream?.end();
      this.stream = null;
      if (reconnect && !this.stopped) this.scheduleReconnect();
      else throw error;
    }
  }

  private handleChunk(chunk: Uint8Array): void {
    this.buffer += new TextDecoder().decode(chunk);
    let newline = this.buffer.indexOf("\n");
    while (newline >= 0) {
      const line = this.buffer.slice(0, newline).trim();
      this.buffer = this.buffer.slice(newline + 1);
      newline = this.buffer.indexOf("\n");
      if (line === "") continue;
      let parsed: RecordValue | null = null;
      try {
        parsed = asRecord(JSON.parse(line));
      } catch {
        this.diagnostic("discarded an unparseable socket line");
      }
      if (!parsed) continue;
      const error = asRecord(parsed["error"]);
      if (error && this.acknowledgement) {
        const acknowledgement = this.acknowledgement;
        this.acknowledgement = null;
        acknowledgement.reject(
          new Error(String(error["message"] ?? error["code"] ?? "subscription rejected")),
        );
        continue;
      }
      const result = asRecord(parsed["result"]);
      if (result?.["type"] === "subscription_started" && this.acknowledgement) {
        this.reconciling = true;
        const acknowledge = this.acknowledgement;
        this.acknowledgement = null;
        acknowledge.resolve();
        continue;
      }
      const event = typeof parsed["event"] === "string" ? parsed["event"] : null;
      const data = asRecord(parsed["data"]);
      if (!event || !data) continue;
      if (this.reconciling) this.queuedEvents.push({ event, data });
      else void this.handleEvent(event, data);
    }
  }

  private async handleEvent(event: string, data: RecordValue): Promise<void> {
    for (const trigger of this.tracker.handleEvent(event, data)) await this.publishMerge(trigger);
    for (const trigger of this.reapTracker.handleEvent(event, data)) await this.publishReap(trigger);
  }

  private async publishMerge(trigger: CandidateTrigger): Promise<void> {
    const candidate = candidateFromTrigger(trigger, this.options.projectRoots, this.options.selfPaneId);
    if (candidate) await this.publish(candidate);
  }

  private async publishReap(trigger: ReapTrigger): Promise<void> {
    const candidate = reapCandidateFromTrigger(trigger, this.options.projectRoots, this.options.selfPaneId);
    if (candidate) await this.publish(candidate);
  }

  private async publish(candidate: RecordValue): Promise<void> {
    const line = JSON.stringify(candidate);
    process.stdout.write(`${line}\n`);
    if (this.options.wakeSelf) await this.wakeSelf(line);
  }

  private async listAgents(): Promise<RecordValue[]> {
    const result = await this.call("agent.list", {});
    const agents = Array.isArray(result["agents"]) ? result["agents"] : [];
    return agents.map(asRecord).filter((row): row is RecordValue => row !== null);
  }

  private async wakeSelf(line: string): Promise<void> {
    if (this.selfSessionId === undefined) this.selfSessionId = await this.findSelfSession();
    if (!this.selfSessionId) {
      this.diagnostic("cannot self-wake: this pane has no reported agent session");
      return;
    }
    const message = [
      `<supervisor_event>${line}</supervisor_event>`,
      "Automated supervisor wake — inspect this exact candidate and continue the /supervisor loop.",
    ].join("\n");
    const child = spawn("agentsurface", ["message", this.selfSessionId, message], {
      stdio: ["ignore", "ignore", "pipe"],
      env: process.env,
    });
    let error = "";
    child.stderr?.on("data", (chunk) => {
      error += String(chunk);
    });
    await new Promise<void>((resolvePromise) => child.once("close", () => resolvePromise()));
    if (child.exitCode !== 0) this.diagnostic(`self-wake failed: ${error.trim() || `exit ${child.exitCode}`}`);
  }

  private async findSelfSession(): Promise<string | null> {
    if (!this.options.selfPaneId) return null;
    const result = await this.call("pane.get", { pane_id: this.options.selfPaneId });
    const pane = asRecord(result["pane"]) ?? result;
    const session = asRecord(pane["agent_session"]);
    return session && typeof session["value"] === "string" ? session["value"] : null;
  }

  private call(method: string, params: RecordValue): Promise<RecordValue> {
    return new Promise((resolvePromise, rejectPromise) => {
      let response = "";
      let settled = false;
      void Bun.connect({
        unix: this.options.socketPath,
        socket: {
          open: (socket) => socket.write(`${JSON.stringify({ id: `supervisor:${method}`, method, params })}\n`),
          data: (socket, chunk) => {
            response += new TextDecoder().decode(chunk);
            const newline = response.indexOf("\n");
            if (newline < 0 || settled) return;
            settled = true;
            socket.end();
            try {
              const envelope = asRecord(JSON.parse(response.slice(0, newline)));
              const error = envelope ? asRecord(envelope["error"]) : null;
              const result = envelope ? asRecord(envelope["result"]) : null;
              if (error) rejectPromise(new Error(String(error["message"] ?? error["code"] ?? method)));
              else if (result) resolvePromise(result);
              else rejectPromise(new Error(`${method} returned no result`));
            } catch (error) {
              rejectPromise(error);
            }
          },
          close: () => {
            if (!settled) rejectPromise(new Error(`${method} connection closed without a response`));
          },
          error: (_socket, error) => rejectPromise(error),
        },
      }).catch(rejectPromise);
    });
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer || this.stopped) return;
    const delay = Math.min(500 * 2 ** Math.min(this.failures++, 10), 30_000);
    this.diagnostic(`disconnected; reconnecting in ${delay}ms`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      void this.connect(true);
    }, delay);
  }

  private diagnostic(message: string): void {
    process.stderr.write(`supervisor watch: ${message}\n`);
  }
}

function usage(): string {
  return `Usage: watch.ts [--project-root <path>]... [--socket <path>] [--wake-self] [--once]\n\nEmits merge_candidate and reap_candidate JSON objects, one per line, from peer and workspace lifecycle events.\n`;
}

export function parseOptions(argv: string[]): WatchOptions {
  const parsed = parseArgs({
    args: argv,
    options: {
      "project-root": { type: "string", multiple: true },
      socket: { type: "string" },
      "wake-self": { type: "boolean", default: false },
      once: { type: "boolean", default: false },
      help: { type: "boolean", short: "h", default: false },
    },
    strict: true,
  });
  if (parsed.values.help) {
    process.stdout.write(usage());
    process.exit(0);
  }
  const roots = parsed.values["project-root"] ?? defaultProjectRoots();
  return {
    socketPath:
      parsed.values.socket ??
      process.env.HERDR_SOCKET_PATH ??
      resolve(homedir(), ".config", "herdr", "herdr.sock"),
    projectRoots: roots.map(normalizePath),
    selfPaneId: process.env.HERDR_PANE_ID ?? null,
    wakeSelf: parsed.values["wake-self"] ?? false,
    once: parsed.values.once ?? false,
  };
}

if (import.meta.main) {
  const options = parseOptions(process.argv.slice(2));
  const watcher = new HerdrWatcher(options);
  const stop = () => {
    watcher.stop();
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  if (options.once) await watcher.runOnce();
  else {
    watcher.start();
    await new Promise(() => {});
  }
}
