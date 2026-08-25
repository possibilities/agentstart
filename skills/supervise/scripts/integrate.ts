#!/usr/bin/env bun

import { existsSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  defaultProjectRoots,
  findTrunkWorktree,
  gitValue,
  normalizePath,
  pathIsWithin,
  resolveCommonDir,
  resolveTrunk,
  runGit,
} from "./git.ts";

interface ResultEnvelope {
  schema_version: 1;
  ok: boolean;
  code: string;
  message: string;
  source?: string;
  expected_head?: string;
  trunk_branch?: string;
  trunk_remote?: string;
  trunk_worktree?: string;
  trunk_head?: string;
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

  // The trunk is whatever this repository integrates into, and the remote is
  // the trunk's own upstream rather than a hardcoded `origin`. In a maintained
  // fork those differ on purpose: `origin` is the upstream project nobody here
  // may write to, and publishing a peer's work there is the one mistake this
  // resolution exists to make impossible.
  const trunk = resolveTrunk(worktree);
  const trunkRecord = findTrunkWorktree(worktree, trunk);
  if (!trunkRecord) {
    fail(40, "trunk_worktree_missing", `no local worktree has ${trunk.ref} checked out`, {
      source,
      trunk_branch: trunk.branch,
    });
  }
  const trunkWorktree = normalizePath(trunkRecord.path);
  if (!pathIsWithin(trunkWorktree, roots)) {
    fail(12, "repository_outside_roots", "the local trunk worktree is outside the configured project roots", {
      source,
      trunk_branch: trunk.branch,
      trunk_worktree: trunkWorktree,
    });
  }
  if (gitValue(trunkWorktree, ["symbolic-ref", "--quiet", "HEAD"]) !== trunk.ref) {
    fail(40, "trunk_not_checked_out", "the selected trunk worktree no longer has the trunk checked out", {
      trunk_branch: trunk.branch,
      trunk_worktree: trunkWorktree,
    });
  }
  const inProgress = operationInProgress(trunkWorktree);
  if (inProgress) {
    fail(40, "trunk_operation_in_progress", "the local trunk already has an unfinished Git operation", {
      trunk_branch: trunk.branch,
      trunk_worktree: trunkWorktree,
      detail: inProgress,
    });
  }

  const fetch = runGit(
    trunkWorktree,
    ["fetch", "--prune", trunk.remote, `+refs/heads/${trunk.remote_branch}:${trunk.remote_ref}`],
    120_000,
  );
  if (fetch.code !== 0) {
    fail(20, "fetch_failed", `could not refresh ${trunk.remote}/${trunk.remote_branch}`, {
      trunk_branch: trunk.branch,
      trunk_remote: trunk.remote,
      trunk_worktree: trunkWorktree,
      detail: fetch.stderr.trim() || fetch.stdout.trim(),
    });
  }
  sourceStillReady(source, expectedHead);

  let trunkHead = gitValue(trunkWorktree, ["rev-parse", trunk.ref]);
  const remoteHead = gitValue(trunkWorktree, ["rev-parse", trunk.remote_ref]);
  if (!trunkHead || !remoteHead) {
    fail(40, "trunk_state_unreadable", "the local trunk or its remote could not be resolved", {
      trunk_branch: trunk.branch,
      trunk_remote: trunk.remote,
      trunk_worktree: trunkWorktree,
    });
  }

  if (!isAncestor(trunkWorktree, remoteHead, trunkHead)) {
    if (!isAncestor(trunkWorktree, trunkHead, remoteHead)) {
      fail(30, "trunk_remote_diverged", `local ${trunk.branch} and ${trunk.remote}/${trunk.remote_branch} have diverged`, {
        trunk_branch: trunk.branch,
        trunk_remote: trunk.remote,
        trunk_worktree: trunkWorktree,
        trunk_head: trunkHead,
        remote_head: remoteHead,
      });
    }
    const update = runGit(trunkWorktree, ["merge", "--ff-only", remoteHead], 120_000);
    if (update.code !== 0) {
      fail(40, "trunk_update_refused", `Git could not fast-forward local ${trunk.branch} to its remote`, {
        trunk_branch: trunk.branch,
        trunk_remote: trunk.remote,
        trunk_worktree: trunkWorktree,
        trunk_head: trunkHead,
        remote_head: remoteHead,
        detail: update.stderr.trim() || update.stdout.trim(),
      });
    }
    trunkHead = remoteHead;
  }

  sourceStillReady(source, expectedHead);
  if (!isAncestor(trunkWorktree, trunkHead, expectedHead)) {
    fail(30, "source_needs_reconciliation", `the approved commit is not a fast-forward from current local ${trunk.branch}`, {
      source,
      expected_head: expectedHead,
      trunk_branch: trunk.branch,
      trunk_worktree: trunkWorktree,
      trunk_head: trunkHead,
      remote_head: remoteHead,
    });
  }

  const integrate = runGit(trunkWorktree, ["merge", "--ff-only", expectedHead], 120_000);
  if (integrate.code !== 0) {
    fail(40, "local_integration_refused", "Git refused the fast-forward into the local trunk", {
      source,
      expected_head: expectedHead,
      trunk_branch: trunk.branch,
      trunk_worktree: trunkWorktree,
      trunk_head: trunkHead,
      detail: integrate.stderr.trim() || integrate.stdout.trim(),
    });
  }
  const integratedHead = gitValue(trunkWorktree, ["rev-parse", trunk.ref]);
  if (integratedHead !== expectedHead) {
    fail(40, "local_integration_mismatch", "the local trunk did not reach the approved commit", {
      expected_head: expectedHead,
      trunk_branch: trunk.branch,
      trunk_worktree: trunkWorktree,
      trunk_head: integratedHead ?? undefined,
    });
  }

  const push = runGit(
    trunkWorktree,
    ["push", "--porcelain", trunk.remote, `${trunk.ref}:refs/heads/${trunk.remote_branch}`],
    120_000,
  );
  if (push.code !== 0) {
    fail(20, "push_failed", `the local trunk contains the work, but pushing ${trunk.remote}/${trunk.remote_branch} failed`, {
      source,
      expected_head: expectedHead,
      trunk_branch: trunk.branch,
      trunk_remote: trunk.remote,
      trunk_worktree: trunkWorktree,
      trunk_head: integratedHead,
      detail: push.stderr.trim() || push.stdout.trim(),
    });
  }

  const verify = runGit(
    trunkWorktree,
    ["ls-remote", "--exit-code", trunk.remote, `refs/heads/${trunk.remote_branch}`],
    120_000,
  );
  const publishedHead = verify.code === 0 ? verify.stdout.trim().split(/\s+/)[0]?.toLowerCase() : null;
  if (publishedHead !== expectedHead) {
    fail(20, "push_verification_failed", `the push returned successfully but ${trunk.remote}/${trunk.remote_branch} did not verify at the approved commit`, {
      source,
      expected_head: expectedHead,
      trunk_branch: trunk.branch,
      trunk_remote: trunk.remote,
      trunk_worktree: trunkWorktree,
      trunk_head: integratedHead,
      remote_head: publishedHead ?? undefined,
      detail: verify.stderr.trim(),
    });
  }

  finish(0, {
    schema_version: 1,
    ok: true,
    code: "integrated_and_pushed",
    message: `the approved commit is local ${trunk.branch} and ${trunk.remote}/${trunk.remote_branch}`,
    source,
    expected_head: expectedHead,
    trunk_branch: trunk.branch,
    trunk_remote: trunk.remote,
    trunk_worktree: trunkWorktree,
    trunk_head: integratedHead,
    remote_head: publishedHead,
  });
}
