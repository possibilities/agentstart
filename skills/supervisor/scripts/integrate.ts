#!/usr/bin/env bun

import { existsSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  defaultProjectRoots,
  findMainWorktree,
  gitValue,
  normalizePath,
  pathIsWithin,
  resolveCommonDir,
  runGit,
} from "./git.ts";

interface ResultEnvelope {
  schema_version: 1;
  ok: boolean;
  code: string;
  message: string;
  source?: string;
  expected_head?: string;
  main_worktree?: string;
  main_head?: string;
  remote_head?: string;
  detail?: string;
}

function finish(exitCode: number, result: ResultEnvelope): never {
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exit(exitCode);
}

function fail(exitCode: number, code: string, message: string, extras: Partial<ResultEnvelope> = {}): never {
  finish(exitCode, { schema_version: 1, ok: false, code, message, ...extras });
}

function operationInProgress(worktree: string): string | null {
  const names = ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"];
  for (const name of names) {
    const path = gitValue(worktree, ["rev-parse", "--git-path", name]);
    if (path && existsSync(isAbsolute(path) ? path : resolve(worktree, path))) return name;
  }
  return null;
}

function isAncestor(repository: string, ancestor: string, descendant: string): boolean {
  return runGit(repository, ["merge-base", "--is-ancestor", ancestor, descendant]).code === 0;
}

function sourceStillReady(source: string, expectedHead: string): void {
  const actual = gitValue(source, ["rev-parse", "HEAD"]);
  if (actual !== expectedHead) {
    fail(10, "source_head_changed", "the peer worktree moved after readiness approval", {
      source,
      expected_head: expectedHead,
      detail: actual ?? "HEAD is unreadable",
    });
  }
  const status = runGit(source, ["status", "--porcelain=v1", "--untracked-files=normal"]);
  if (status.code !== 0 || status.stdout.trim() !== "") {
    fail(11, "source_not_clean", "the peer worktree is not clean", {
      source,
      expected_head: expectedHead,
      detail: status.stdout.trim() || status.stderr.trim(),
    });
  }
}

function usage(): string {
  return "Usage: integrate.ts --source <worktree> --expected-head <full-sha> [--project-root <path>]...\n";
}

if (import.meta.main) {
  const parsed = parseArgs({
    args: process.argv.slice(2),
    options: {
      source: { type: "string" },
      "expected-head": { type: "string" },
      "project-root": { type: "string", multiple: true },
      help: { type: "boolean", short: "h", default: false },
    },
    strict: true,
  });
  if (parsed.values.help) {
    process.stdout.write(usage());
    process.exit(0);
  }

  const sourceArg = parsed.values.source;
  const expectedArg = parsed.values["expected-head"];
  if (!sourceArg || !expectedArg) fail(64, "usage", usage().trim());
  if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/i.test(expectedArg)) {
    fail(64, "expected_head_not_full", "--expected-head must be a full Git object id");
  }

  const source = normalizePath(sourceArg);
  const expectedHead = expectedArg.toLowerCase();
  const roots = (parsed.values["project-root"] ?? defaultProjectRoots()).map(normalizePath);
  const worktree = gitValue(source, ["rev-parse", "--show-toplevel"]);
  const commonDir = resolveCommonDir(source);
  if (!worktree || !commonDir) fail(12, "source_not_repository", "the source is not a Git worktree", { source });

  const resolvedExpected = gitValue(source, ["rev-parse", "--verify", `${expectedHead}^{commit}`]);
  if (resolvedExpected?.toLowerCase() !== expectedHead) {
    fail(12, "expected_head_missing", "the approved commit is not present in the source repository", {
      source,
      expected_head: expectedHead,
    });
  }
  sourceStillReady(source, expectedHead);

  const main = findMainWorktree(worktree);
  if (!main) fail(40, "main_worktree_missing", "no local worktree has refs/heads/main checked out", { source });
  const mainWorktree = normalizePath(main.path);
  if (!pathIsWithin(mainWorktree, roots)) {
    fail(12, "repository_outside_roots", "the local main worktree is outside the configured project roots", {
      source,
      main_worktree: mainWorktree,
    });
  }
  if (gitValue(mainWorktree, ["symbolic-ref", "--quiet", "HEAD"]) !== "refs/heads/main") {
    fail(40, "main_not_checked_out", "the selected main worktree no longer has main checked out", {
      main_worktree: mainWorktree,
    });
  }
  const inProgress = operationInProgress(mainWorktree);
  if (inProgress) {
    fail(40, "main_operation_in_progress", "local main already has an unfinished Git operation", {
      main_worktree: mainWorktree,
      detail: inProgress,
    });
  }

  const fetch = runGit(mainWorktree, ["fetch", "--prune", "origin", "+refs/heads/main:refs/remotes/origin/main"], 120_000);
  if (fetch.code !== 0) {
    fail(20, "fetch_failed", "could not refresh origin/main", {
      main_worktree: mainWorktree,
      detail: fetch.stderr.trim() || fetch.stdout.trim(),
    });
  }
  sourceStillReady(source, expectedHead);

  let mainHead = gitValue(mainWorktree, ["rev-parse", "refs/heads/main"]);
  const remoteHead = gitValue(mainWorktree, ["rev-parse", "refs/remotes/origin/main"]);
  if (!mainHead || !remoteHead) {
    fail(40, "main_state_unreadable", "local main or origin/main could not be resolved", {
      main_worktree: mainWorktree,
    });
  }

  if (!isAncestor(mainWorktree, remoteHead, mainHead)) {
    if (!isAncestor(mainWorktree, mainHead, remoteHead)) {
      fail(30, "main_remote_diverged", "local main and origin/main have diverged", {
        main_worktree: mainWorktree,
        main_head: mainHead,
        remote_head: remoteHead,
      });
    }
    const update = runGit(mainWorktree, ["merge", "--ff-only", remoteHead], 120_000);
    if (update.code !== 0) {
      fail(40, "main_update_refused", "Git could not fast-forward local main to origin/main", {
        main_worktree: mainWorktree,
        main_head: mainHead,
        remote_head: remoteHead,
        detail: update.stderr.trim() || update.stdout.trim(),
      });
    }
    mainHead = remoteHead;
  }

  sourceStillReady(source, expectedHead);
  if (!isAncestor(mainWorktree, mainHead, expectedHead)) {
    fail(30, "source_needs_reconciliation", "the approved commit is not a fast-forward from current local main", {
      source,
      expected_head: expectedHead,
      main_worktree: mainWorktree,
      main_head: mainHead,
      remote_head: remoteHead,
    });
  }

  const integrate = runGit(mainWorktree, ["merge", "--ff-only", expectedHead], 120_000);
  if (integrate.code !== 0) {
    fail(40, "local_integration_refused", "Git refused the fast-forward into local main", {
      source,
      expected_head: expectedHead,
      main_worktree: mainWorktree,
      main_head: mainHead,
      detail: integrate.stderr.trim() || integrate.stdout.trim(),
    });
  }
  const integratedHead = gitValue(mainWorktree, ["rev-parse", "refs/heads/main"]);
  if (integratedHead !== expectedHead) {
    fail(40, "local_integration_mismatch", "local main did not reach the approved commit", {
      expected_head: expectedHead,
      main_worktree: mainWorktree,
      main_head: integratedHead ?? undefined,
    });
  }

  const push = runGit(
    mainWorktree,
    ["push", "--porcelain", "origin", "refs/heads/main:refs/heads/main"],
    120_000,
  );
  if (push.code !== 0) {
    fail(20, "push_failed", "local main contains the work, but pushing origin/main failed", {
      source,
      expected_head: expectedHead,
      main_worktree: mainWorktree,
      main_head: integratedHead,
      detail: push.stderr.trim() || push.stdout.trim(),
    });
  }

  const verify = runGit(mainWorktree, ["ls-remote", "--exit-code", "origin", "refs/heads/main"], 120_000);
  const publishedHead = verify.code === 0 ? verify.stdout.trim().split(/\s+/)[0]?.toLowerCase() : null;
  if (publishedHead !== expectedHead) {
    fail(20, "push_verification_failed", "the push returned successfully but origin/main did not verify at the approved commit", {
      source,
      expected_head: expectedHead,
      main_worktree: mainWorktree,
      main_head: integratedHead,
      remote_head: publishedHead ?? undefined,
      detail: verify.stderr.trim(),
    });
  }

  finish(0, {
    schema_version: 1,
    ok: true,
    code: "integrated_and_pushed",
    message: "the approved commit is local main and origin/main",
    source,
    expected_head: expectedHead,
    main_worktree: mainWorktree,
    main_head: integratedHead,
    remote_head: publishedHead,
  });
}
