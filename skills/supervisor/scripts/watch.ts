#!/usr/bin/env bun

import { spawn } from "node:child_process";
import { parseArgs } from "node:util";
import {
  type OwnershipProvider,
  type RecordValue,
  type WorktreeOwner,
  asRecord,
  callHerdr,
  defaultSocketPath,
  listAgents,
  ownerOf,
  paneId,
  sessionName,
} from "./ade.ts";
import { defaultProjectRoots, inspectCandidate, inspectWorktree, normalizePath } from "./git.ts";
import { buildRoster, place } from "./roster.ts";
import { type DiscoveredWorktree, WorktreeDiscovery } from "./worktrees.ts";

type AgentStatus = "idle" | "working" | "blocked" | "done" | "unknown";

export type { OwnershipProvider, RecordValue, WorktreeOwner };

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
  discover: boolean;
  sweepIntervalSeconds: number;
}

/**
 * The single exit for every candidate, wherever it was discovered. Holding the
 * dedupe here is what lets Git-driven discovery and ADE lifecycle events find
 * the same commit without announcing it twice.
 */
export class CandidateSink {
  private readonly announced = new Set<string>();
  private readonly emit: (line: string) => Promise<void>;

  constructor(emit: (line: string) => Promise<void>) {
    this.emit = emit;
  }

  async publish(candidate: RecordValue): Promise<void> {
    const key = `${candidate["type"]}:${candidate["worktree"]}:${candidate["head"]}:${
      Array.isArray(candidate["blockers"]) ? candidate["blockers"].join(",") : ""
    }`;
    if (this.announced.has(key)) return;
    this.announced.add(key);
    await this.emit(JSON.stringify(candidate));
  }

  /** Emitted whole, never deduped: a roster is a standing picture, not a change. */
  async announce(record: RecordValue): Promise<void> {
    await this.emit(JSON.stringify(record));
  }
}

const SUBSCRIPTIONS = [
  { type: "pane.created" },
  { type: "pane.updated" },
  { type: "pane.closed" },
  { type: "pane.exited" },
  { type: "pane.agent_detected" },
  { type: "workspace.closed" },
];

function asStatus(value: unknown): AgentStatus {
  return value === "idle" || value === "working" || value === "blocked" || value === "done"
    ? value
    : "unknown";
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
    session_name: sessionName(agent),
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
        session_name: sessionName(agent),
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

  private readonly sink: CandidateSink;

  constructor(options: WatchOptions, sink: CandidateSink) {
    this.options = options;
    this.sink = sink;
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
    await this.sink.publish(candidate);
  }

  /** Live agents keyed by the worktree they are working in. */
  async owner(worktree: string): Promise<WorktreeOwner | null> {
    const rows = await this.agentRows();
    return rows ? ownerOf(rows, worktree, this.options.selfPaneId) : null;
  }

  async available(): Promise<boolean> {
    return (await this.agentRows()) !== null;
  }

  private async agentRows(): Promise<RecordValue[] | null> {
    try {
      return await this.listAgents();
    } catch (error) {
      this.diagnostic(`ownership lookup failed: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }

  private listAgents(): Promise<RecordValue[]> {
    return listAgents(this.options.socketPath);
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
    return callHerdr(this.options.socketPath, method, params);
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

/**
 * A worktree Git reported, turned into a candidate, or `null` when it holds
 * nothing for the supervisor. It becomes a merge candidate when an ADE can
 * name the agent working there — the readiness handshake needs someone to ask
 * — and an unowned candidate otherwise, which the supervisor brings to its
 * human instead of merging on its own authority.
 */
export async function candidateFromWorktree(
  worktree: DiscoveredWorktree,
  ownership: OwnershipProvider | null,
): Promise<RecordValue | null> {
  const { repository: _repository, state, ...identity } = worktree;
  const owner = ownership ? await ownership.owner(worktree.worktree) : null;

  // The integration target is not a candidate for anything.
  if (state === "main") return null;

  // A checkout somebody opened is not work. No commit was ever made here and
  // nothing is uncommitted, so there is nothing to integrate and nothing to
  // lose with the directory. Its first change of either kind makes it a
  // candidate like any other.
  if (!worktree.worked) return null;

  // Landed work has nothing left to integrate, which is precisely when a
  // worktree stops being work and starts being a directory. Say so — including
  // the moment the supervisor's own fast-forward puts it in this state — rather
  // than waiting for an ADE to notice its workspace close.
  if (state === "landed") {
    const placed = place(worktree, owner);
    // A quiet worktree is not news: the agent that did the work is still
    // sitting there. Nothing is at stake, and reporting it buries the
    // worktrees that need a human.
    if (placed.category === "quiet") return null;
    // Uncommitted work under a live session is the one landed state not worth
    // announcing: it changes with every file the agent saves. Left behind by a
    // session that is gone, the same state is exactly what a human must hear.
    if (!placed.clean && owner) return null;
    return {
      schema_version: 1,
      type: "removable_worktree",
      reason: "discovered",
      removable: placed.removable,
      blockers: placed.blockers,
      owner,
      ...identity,
    };
  }

  if (!owner) {
    return {
      schema_version: 1,
      type: "unowned_candidate",
      reason: "discovered",
      ...identity,
    };
  }
  return {
    schema_version: 1,
    type: "merge_candidate",
    reason: "discovered",
    pane_id: owner.pane_id,
    session_id: owner.session_id,
    session_name: owner.session_name,
    harness: owner.harness,
    cwd: worktree.worktree,
    ...identity,
  };
}

export function startDiscovery(
  options: WatchOptions,
  sink: CandidateSink,
  ownership: OwnershipProvider | null,
): WorktreeDiscovery {
  const discovery = new WorktreeDiscovery({
    projectRoots: options.projectRoots,
    sweepIntervalSeconds: options.sweepIntervalSeconds,
    onWorktree: async (worktree) => {
      try {
        const candidate = await candidateFromWorktree(worktree, ownership);
        if (candidate) await sink.publish(candidate);
        // An unreported worktree stays unannounced, so a later scan sees it
        // afresh: ownership can change without Git moving a single ref.
        return candidate !== null;
      } catch (error) {
        process.stderr.write(
          `supervisor watch: discovery publish failed: ${error instanceof Error ? error.message : String(error)}\n`,
        );
        return false;
      }
    },
    onDiagnostic: (message) => process.stderr.write(`supervisor watch: ${message}\n`),
  });
  discovery.start();
  return discovery;
}

function usage(): string {
  return `Usage: watch.ts [--project-root <path>]... [--socket <path>] [--wake-self] [--once]
                [--no-discover] [--sweep-interval <seconds>]

Emits one roster JSON object at startup, then merge_candidate,
unowned_candidate, removable_worktree, and reap_candidate objects, one per
line.

Worktrees are discovered from Git itself — each repository's worktree registry,
watched on the filesystem — so a worktree created by any tool is found. Agent
lifecycle events from the ADE supply session ownership and workspace closure.

  --no-discover               rely only on ADE lifecycle events
  --sweep-interval <seconds>  safety rescan cadence, 0 to disable (default 300)
`;
}

function parseSweepInterval(value: string | undefined): number {
  if (value === undefined) return 300;
  const seconds = Number.parseInt(value, 10);
  if (!Number.isFinite(seconds) || seconds < 0) {
    throw new Error(`--sweep-interval expects a non-negative number of seconds, got ${value}`);
  }
  return seconds;
}

export function parseOptions(argv: string[]): WatchOptions {
  const parsed = parseArgs({
    args: argv,
    options: {
      "project-root": { type: "string", multiple: true },
      socket: { type: "string" },
      "wake-self": { type: "boolean", default: false },
      once: { type: "boolean", default: false },
      "no-discover": { type: "boolean", default: false },
      "sweep-interval": { type: "string" },
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
    socketPath: parsed.values.socket ?? defaultSocketPath(),
    projectRoots: roots.map(normalizePath),
    selfPaneId: process.env.HERDR_PANE_ID ?? null,
    wakeSelf: parsed.values["wake-self"] ?? false,
    once: parsed.values.once ?? false,
    discover: !(parsed.values["no-discover"] ?? false),
    sweepIntervalSeconds: parseSweepInterval(parsed.values["sweep-interval"]),
  };
}

if (import.meta.main) {
  const options = parseOptions(process.argv.slice(2));
  const sink = new CandidateSink(async (line) => {
    process.stdout.write(`${line}\n`);
    if (options.wakeSelf) await wake(options, line);
  });
  const watcher = new HerdrWatcher(options, sink);
  let discovery: WorktreeDiscovery | null = null;
  const stop = () => {
    discovery?.stop();
    watcher.stop();
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  // The roster comes first, before any event. A supervisor should open its run
  // knowing everything it watches — what still holds work, what has landed, and
  // what is now removable — rather than assembling that from whichever events
  // happen to fire.
  if (options.discover) {
    await sink.announce(
      await buildRoster(options.projectRoots, watcher, options.once ? "snapshot" : "start"),
    );
  }

  if (options.once) {
    // A single pass still reports every worktree Git knows about, so `--once`
    // remains a complete snapshot rather than only the ADE's live sessions.
    if (options.discover) {
      discovery = startDiscovery({ ...options, sweepIntervalSeconds: 0 }, sink, watcher);
      discovery.drainNow();
    }
    await watcher.runOnce();
    discovery?.stop();
  } else {
    watcher.start();
    if (options.discover) discovery = startDiscovery(options, sink, watcher);
    await new Promise(() => {});
  }
}
