#!/usr/bin/env bun

import { appendFileSync, closeSync, fsyncSync, mkdirSync, openSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  defaultProjectRoots,
  gitValue,
  inspectWorktree,
  listWorktrees,
  normalizePath,
  runGit,
} from "./git.ts";

interface AgentIdentity {
  harness: string;
  session_id: string;
  pane_id: string;
}

interface ReapResult {
  schema_version: 1;
  ok: boolean;
  code: string;
  message: string;
  worktree?: string;
  branch?: string;
  head?: string;
  log?: string;
  detail?: string;
}

function finish(exitCode: number, result: ReapResult): never {
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exit(exitCode);
}

function fail(exitCode: number, code: string, message: string, extras: Partial<ReapResult> = {}): never {
  finish(exitCode, { schema_version: 1, ok: false, code, message, ...extras });
}

function usage(): string {
  return [
    "Usage: reap.ts --worktree <path> --expected-branch <branch> --expected-head <full-sha>",
    "               --workspace-id <id> --agent-json <json> [--agent-json <json>]...",
    "               [--project-root <path>]... [--log <jsonl-path>]",
  ].join("\n");
}

function parseAgent(value: string): AgentIdentity {
  const parsed = JSON.parse(value) as Partial<AgentIdentity>;
  if (
    typeof parsed.harness !== "string" ||
    typeof parsed.session_id !== "string" ||
    typeof parsed.pane_id !== "string"
  ) {
    throw new Error("each --agent-json must contain harness, session_id, and pane_id strings");
  }
  return { harness: parsed.harness, session_id: parsed.session_id, pane_id: parsed.pane_id };
}

if (import.meta.main) {
  const parsed = parseArgs({
    args: process.argv.slice(2),
    options: {
      worktree: { type: "string" },
      "expected-branch": { type: "string" },
      "expected-head": { type: "string" },
      "workspace-id": { type: "string" },
      "agent-json": { type: "string", multiple: true },
      "project-root": { type: "string", multiple: true },
      log: { type: "string" },
      help: { type: "boolean", short: "h", default: false },
    },
    strict: true,
  });
  if (parsed.values.help) {
    process.stdout.write(`${usage()}\n`);
    process.exit(0);
  }

  const worktreeArg = parsed.values.worktree;
  const expectedBranch = parsed.values["expected-branch"];
  const expectedArg = parsed.values["expected-head"];
  const workspaceId = parsed.values["workspace-id"];
  const agentValues = parsed.values["agent-json"] ?? [];
  if (!worktreeArg || !expectedBranch || !expectedArg || !workspaceId || agentValues.length === 0) {
    fail(64, "usage", usage());
  }
  if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/i.test(expectedArg)) {
    fail(64, "expected_head_not_full", "--expected-head must be a full Git object id");
  }
  if (
    expectedBranch === "main" ||
    runGit(process.cwd(), ["check-ref-format", "--branch", expectedBranch]).code !== 0
  ) {
    fail(12, "branch_not_reapable", "the expected branch is main or is not a valid local branch name");
  }

  let agents: AgentIdentity[];
  try {
    agents = agentValues.map(parseAgent);
  } catch (error) {
    fail(64, "agent_identity_invalid", error instanceof Error ? error.message : String(error));
  }

  const roots = (parsed.values["project-root"] ?? defaultProjectRoots()).map(normalizePath);
  const worktree = normalizePath(worktreeArg);
  const expectedHead = expectedArg.toLowerCase();
  const identity = inspectWorktree(worktree, roots);
  if (!identity) {
    fail(12, "worktree_not_reapable", "the path is not a registered worktree owned by a configured project root", {
      worktree,
    });
  }
  if (identity.main_worktree === worktree) {
    fail(12, "main_worktree_refused", "the local main worktree can never be reaped", { worktree });
  }
  if (identity.branch !== expectedBranch || identity.head.toLowerCase() !== expectedHead) {
    fail(10, "worktree_identity_changed", "the worktree branch or HEAD changed after its close event", {
      worktree,
      branch: identity.branch ?? undefined,
      head: identity.head,
    });
  }
  if (!identity.clean) {
    fail(11, "worktree_not_clean", "the closed worktree has uncommitted state and was preserved", {
      worktree,
      branch: identity.branch,
      head: identity.head,
    });
  }
  if (!listWorktrees(identity.main_worktree).some((entry) => normalizePath(entry.path) === worktree)) {
    fail(12, "worktree_not_registered", "Git no longer lists the exact worktree path", { worktree });
  }

  const logPath = normalizePath(
    parsed.values.log ?? resolve(homedir(), ".local", "state", "agentstart", "supervisor", "reaped.jsonl"),
  );
  mkdirSync(dirname(logPath), { recursive: true, mode: 0o700 });
  let logFd: number;
  try {
    logFd = openSync(logPath, "a", 0o600);
  } catch (error) {
    fail(40, "reap_log_unavailable", "the durable reap log could not be opened; the worktree was preserved", {
      worktree,
      log: logPath,
      detail: error instanceof Error ? error.message : String(error),
    });
  }

  const receipt = {
    schema_version: 1,
    recorded_at: new Date().toISOString(),
    workspace_id: workspaceId,
    agents,
    worktree,
    common_dir: identity.common_dir,
    main_worktree: identity.main_worktree,
    branch: expectedBranch,
    head: expectedHead,
  };
  try {
    appendFileSync(logFd, `${JSON.stringify({ ...receipt, event: "reap_started" })}\n`);
    fsyncSync(logFd);
  } catch (error) {
    closeSync(logFd);
    fail(40, "reap_log_unavailable", "the durable reap intent could not be recorded; the worktree was preserved", {
      worktree,
      log: logPath,
      detail: error instanceof Error ? error.message : String(error),
    });
  }

  const remove = runGit(identity.main_worktree, ["worktree", "remove", "--", worktree], 120_000);
  if (remove.code !== 0) {
    appendFileSync(
      logFd,
      `${JSON.stringify({
        ...receipt,
        event: "reap_failed",
        recorded_at: new Date().toISOString(),
        detail: remove.stderr.trim() || remove.stdout.trim(),
      })}\n`,
    );
    fsyncSync(logFd);
    closeSync(logFd);
    fail(20, "worktree_remove_failed", "Git refused to remove the closed worktree", {
      worktree,
      branch: expectedBranch,
      head: expectedHead,
      log: logPath,
      detail: remove.stderr.trim() || remove.stdout.trim(),
    });
  }

  const stillRegistered = listWorktrees(identity.main_worktree).some(
    (entry) => normalizePath(entry.path) === worktree,
  );
  const preservedHead = gitValue(identity.main_worktree, ["rev-parse", `refs/heads/${expectedBranch}`]);
  if (stillRegistered || preservedHead?.toLowerCase() !== expectedHead) {
    appendFileSync(
      logFd,
      `${JSON.stringify({
        ...receipt,
        event: "reap_verification_failed",
        recorded_at: new Date().toISOString(),
        still_registered: stillRegistered,
        preserved_head: preservedHead,
      })}\n`,
    );
    fsyncSync(logFd);
    closeSync(logFd);
    fail(40, "reap_verification_failed", "worktree removal or branch preservation did not verify", {
      worktree,
      branch: expectedBranch,
      head: expectedHead,
      log: logPath,
    });
  }

  appendFileSync(logFd, `${JSON.stringify({ ...receipt, event: "reaped", recorded_at: new Date().toISOString() })}\n`);
  fsyncSync(logFd);
  closeSync(logFd);
  finish(0, {
    schema_version: 1,
    ok: true,
    code: "worktree_reaped",
    message: "the closed clean worktree was removed and its branch was preserved",
    worktree,
    branch: expectedBranch,
    head: expectedHead,
    log: logPath,
  });
}
