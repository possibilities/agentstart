import { homedir } from "node:os";
import { resolve } from "node:path";
import { pathIsWithin } from "./git.ts";

/**
 * The agent development environment, reduced to the two questions the
 * supervisor asks of it: who is working in a given worktree, and what agents
 * are live right now.
 *
 * Discovery is answered by Git alone. This is the other, independent source —
 * the readiness handshake needs a session to talk to, and only the ADE knows
 * that. Herdr is this machine's ADE and supplies the implementation below; any
 * other ADE satisfies the same small contract, and when none can answer, an
 * unowned worktree is still reported rather than silently dropped.
 */

export type RecordValue = Record<string, unknown>;

export interface WorktreeOwner {
  harness: string | null;
  session_id: string;
  /** The session's own name slug, which is what a human calls it. */
  session_name: string | null;
  pane_id: string | null;
}

export interface OwnershipProvider {
  owner(worktree: string): Promise<WorktreeOwner | null>;
  /** Whether the ADE answered at all. Absent means "assume it did". */
  available?(): Promise<boolean>;
}

export function asRecord(value: unknown): RecordValue | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as RecordValue)
    : null;
}

export function paneId(row: RecordValue): string | null {
  return typeof row["pane_id"] === "string" ? row["pane_id"] : null;
}

/**
 * A session's name slug, as the ADE knows it.
 *
 * A session id addresses a peer; a slug identifies it to a human. Herdr keeps
 * the slug under `tokens.conversation`, and it is the same string the operator
 * sees on the pane, which is why every human-facing mention of an agent uses
 * it. It can be absent — a session too young to have been named — so
 * `describeSession` below is what callers speak, never the raw field.
 */
export function sessionName(row: RecordValue): string | null {
  const tokens = asRecord(row["tokens"]);
  const slug = tokens && typeof tokens["conversation"] === "string" ? tokens["conversation"] : null;
  return slug && slug.length > 0 ? slug : null;
}

/** How an owner is named in prose: its slug when it has one, its id when it does not. */
export function describeSession(owner: WorktreeOwner): string {
  const label = owner.session_name ?? owner.session_id;
  return owner.harness ? `${owner.harness} ${label}` : label;
}

export function defaultSocketPath(): string {
  return process.env.HERDR_SOCKET_PATH ?? resolve(homedir(), ".config", "herdr", "herdr.sock");
}

/** One request, one response, one connection. */
export function callHerdr(
  socketPath: string,
  method: string,
  params: RecordValue,
): Promise<RecordValue> {
  return new Promise((resolvePromise, rejectPromise) => {
    let response = "";
    let settled = false;
    void Bun.connect({
      unix: socketPath,
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

export async function listAgents(socketPath: string): Promise<RecordValue[]> {
  const result = await callHerdr(socketPath, "agent.list", {});
  const agents = Array.isArray(result["agents"]) ? result["agents"] : [];
  return agents.map(asRecord).filter((row): row is RecordValue => row !== null);
}

/** The live agent working inside `worktree`, from an already-fetched agent list. */
export function ownerOf(
  rows: readonly RecordValue[],
  worktree: string,
  selfPaneId: string | null,
): WorktreeOwner | null {
  for (const row of rows) {
    const id = paneId(row);
    if (!id || id === selfPaneId) continue;
    const cwd = typeof row["cwd"] === "string" ? row["cwd"] : null;
    const foreground = typeof row["foreground_cwd"] === "string" ? row["foreground_cwd"] : null;
    const inside = [cwd, foreground].some((path) => path !== null && pathIsWithin(path, [worktree]));
    if (!inside) continue;
    const session = asRecord(row["agent_session"]);
    const sessionId = session && typeof session["value"] === "string" ? session["value"] : null;
    if (!sessionId) continue;
    return {
      harness: session && typeof session["agent"] === "string" ? session["agent"] : null,
      session_id: sessionId,
      session_name: sessionName(row),
      pane_id: id,
    };
  }
  return null;
}

/**
 * Ownership answered by asking the ADE afresh each time. The watcher holds a
 * live subscription and answers from that; this is for one-shot callers — the
 * roster above all — that must not open a subscription to ask one question.
 */
export class DirectOwnership implements OwnershipProvider {
  private readonly socketPath: string;
  private readonly selfPaneId: string | null;
  private cached: RecordValue[] | null = null;

  constructor(socketPath: string, selfPaneId: string | null) {
    this.socketPath = socketPath;
    this.selfPaneId = selfPaneId;
  }

  /** Whether the ADE answered at all; a roster says so rather than implying nobody is working. */
  async available(): Promise<boolean> {
    return (await this.rows()) !== null;
  }

  async owner(worktree: string): Promise<WorktreeOwner | null> {
    const rows = await this.rows();
    return rows ? ownerOf(rows, worktree, this.selfPaneId) : null;
  }

  private async rows(): Promise<RecordValue[] | null> {
    if (this.cached) return this.cached;
    try {
      this.cached = await listAgents(this.socketPath);
      return this.cached;
    } catch {
      return null;
    }
  }
}
