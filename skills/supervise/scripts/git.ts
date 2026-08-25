import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { existsSync, realpathSync } from "node:fs";

export interface CommandResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface WorktreeRecord {
  path: string;
  head: string | null;
  branch: string | null;
  detached: boolean;
  prunable: string | null;
}

export interface WorktreeIdentity {
  worktree: string;
  common_dir: string;
  /** The branch this repository integrates into, and where it is checked out. */
  trunk_branch: string;
  trunk_worktree: string;
  /** This repository's own supervision instructions, or null where it has none. */
  guidance: string | null;
  branch: string | null;
  head: string;
  trunk_head: string;
  commits_ahead: number;
  commits_behind: number;
  clean: boolean;
}

export function runGit(cwd: string, args: string[], timeout = 15_000): CommandResult {
  const result = spawnSync("git", ["-C", cwd, ...args], {
    encoding: "utf8",
    timeout,
    stdio: ["ignore", "pipe", "pipe"],
  });
  return {
    code: result.status ?? (result.error ? 127 : 0),
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? result.error?.message ?? "",
  };
}

export function gitValue(cwd: string, args: string[]): string | null {
  const result = runGit(cwd, args);
  return result.code === 0 ? result.stdout.trim() : null;
}

export function normalizePath(path: string): string {
  const expanded = path === "~" ? homedir() : path.startsWith("~/") ? resolve(homedir(), path.slice(2)) : path;
  const absolute = isAbsolute(expanded) ? resolve(expanded) : resolve(expanded);
  try {
    return realpathSync.native(absolute);
  } catch {
    return absolute;
  }
}

export function pathIsWithin(path: string, roots: readonly string[]): boolean {
  const candidate = normalizePath(path);
  return roots.some((root) => {
    const relation = relative(normalizePath(root), candidate);
    return relation === "" || (!relation.startsWith("..") && !isAbsolute(relation));
  });
}

export function defaultProjectRoots(): string[] {
  return [resolve(homedir(), "code"), resolve(homedir(), "src")];
}

export function parseWorktrees(output: string): WorktreeRecord[] {
  const records: WorktreeRecord[] = [];
  let current: WorktreeRecord | null = null;

  for (const raw of output.split("\n")) {
    const line = raw.trimEnd();
    if (line === "") {
      if (current) records.push(current);
      current = null;
      continue;
    }
    if (line.startsWith("worktree ")) {
      if (current) records.push(current);
      current = {
        path: line.slice("worktree ".length),
        head: null,
        branch: null,
        detached: false,
        prunable: null,
      };
    } else if (current && line.startsWith("HEAD ")) {
      current.head = line.slice("HEAD ".length);
    } else if (current && line.startsWith("branch ")) {
      current.branch = line.slice("branch ".length);
    } else if (current && line === "detached") {
      current.detached = true;
    } else if (current && (line === "prunable" || line.startsWith("prunable "))) {
      current.prunable = line === "prunable" ? "prunable" : line.slice("prunable ".length);
    }
  }
  if (current) records.push(current);
  return records;
}

export function listWorktrees(repository: string): WorktreeRecord[] {
  const result = runGit(repository, ["worktree", "list", "--porcelain"]);
  return result.code === 0 ? parseWorktrees(result.stdout) : [];
}

/**
 * Worktrees Git still registers whose checkout is present on disk. Git marks a
 * registration whose checkout has been deleted `prunable`; the existence check
 * is a second, independent confirmation for the racy window before Git notices.
 */
export function listLiveWorktrees(repository: string): WorktreeRecord[] {
  return listWorktrees(repository).filter(
    (worktree) => worktree.prunable === null && existsSync(worktree.path),
  );
}

/** Where a repository's trunk configuration is read from. */
export const TRUNK_CONFIG_KEY = "supervisor.trunk";

/**
 * The branch a repository integrates into, and the remote that publishes it.
 *
 * `main` is a default, not a law. A fork under maintenance keeps `main` as an
 * untouched mirror of upstream and does its real integration on a branch of its
 * own, so a supervisor that hardcodes `main` either supervises nothing there or
 * — far worse — fast-forwards a peer's work onto the upstream mirror and pushes
 * it at somebody else's repository.
 *
 * The remote is never configured separately, because Git already knows it: the
 * trunk's own upstream is the branch the operator pulls and pushes by hand, and
 * a supervisor publishing anywhere else would be publishing somewhere nobody
 * asked for. In a fork that upstream is the fork remote, which is exactly what
 * keeps `origin` — the read-only upstream project — out of reach.
 */
export interface Trunk {
  /** Local branch name; `main` unless configured otherwise. */
  branch: string;
  /** `refs/heads/<branch>`. */
  ref: string;
  /** Remote the trunk publishes to, taken from its own upstream. */
  remote: string;
  /** The branch's name on that remote, which need not match the local one. */
  remote_branch: string;
  /** `refs/remotes/<remote>/<remote_branch>`. */
  remote_ref: string;
  /** Whether the branch name was configured rather than defaulted. */
  configured: boolean;
}

export function resolveTrunk(repository: string): Trunk {
  const configured = gitValue(repository, ["config", "--get", TRUNK_CONFIG_KEY]);
  const branch = configured && configured.trim() !== "" ? configured.trim() : "main";

  // A branch tracking another local branch records `.` as its remote, which is
  // a real answer and not a remote to push to. Falling back to `origin` there
  // keeps the default repository behaving exactly as it always has.
  const trackedRemote = gitValue(repository, ["config", "--get", `branch.${branch}.remote`]);
  const remote = trackedRemote && trackedRemote !== "." ? trackedRemote : "origin";
  const merge = gitValue(repository, ["config", "--get", `branch.${branch}.merge`]);
  const remoteBranch = merge?.startsWith("refs/heads/") ? merge.slice("refs/heads/".length) : branch;

  return {
    branch,
    ref: `refs/heads/${branch}`,
    remote,
    remote_branch: remoteBranch,
    remote_ref: `refs/remotes/${remote}/${remoteBranch}`,
    configured: configured !== null && configured.trim() !== "",
  };
}

export function findTrunkWorktree(repository: string, trunk: Trunk): WorktreeRecord | null {
  return listWorktrees(repository).find((worktree) => worktree.branch === trunk.ref) ?? null;
}

export function resolveCommonDir(cwd: string): string | null {
  const value = gitValue(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  return value ? normalizePath(value) : null;
}

/**
 * Whether this checkout is the repository itself rather than a linked worktree.
 *
 * Git registers every added worktree under the common directory and gives it a
 * gitfile pointing back at it; the one checkout registered no such way is the
 * repository root, whose own `.git` *is* the common directory. That is a
 * structural fact and not a branch: the primary checkout is somebody's working
 * directory whatever it happens to have checked out, and assuming it is
 * whichever worktree holds `main` is how a supervisor talks itself into
 * deleting an operator's own directory.
 */
export function isPrimaryWorktree(worktree: string, commonDir: string): boolean {
  return normalizePath(worktree) === normalizePath(dirname(commonDir));
}

/** The file a repository uses to tell a supervisor how it wants to be handled. */
export const GUIDANCE_FILENAME = "SUPERVISE.md";

/**
 * A repository's own supervision instructions, if it keeps any.
 *
 * The supervisor's default reading — a branch ahead of the trunk is finished
 * work waiting to be shipped — is true of most repositories and wrong about
 * some. A fork under maintenance carries long-lived patch branches that are
 * permanently ahead on purpose and are rebuilt into the trunk by a tool of its
 * own, and no amount of general policy can know that from the commit graph.
 * The repository is the only thing that knows, so it is given somewhere to say
 * so, and a supervisor reads it before deciding anything about that repository.
 *
 * The trunk worktree holds the branch of record and is asked first; the
 * primary checkout answers second, which is what lets an operator drop
 * instructions in without committing them. Absent from both, the repository
 * has no special handling and the default reading stands.
 */
export function supervisionGuidance(trunkWorktree: string, commonDir: string): string | null {
  const primary = normalizePath(dirname(commonDir));
  for (const directory of [normalizePath(trunkWorktree), primary]) {
    const candidate = resolve(directory, GUIDANCE_FILENAME);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

export function inspectCandidate(cwd: string, roots: readonly string[]): RepositoryCandidate | null {
  const repository = inspectWorktree(cwd, roots);
  return repository && repository.commits_ahead > 0 ? repository : null;
}

/**
 * What every worktree of one repository shares: which branch is its trunk,
 * where that trunk lives, what it points at, and which common directory
 * registers them all. Resolving this once per scan is what makes surveying
 * settled worktrees affordable — each one then costs a status call and a count
 * instead of a full inspection.
 */
export interface RepositoryContext {
  common_dir: string;
  trunk: Trunk;
  trunk_worktree: string;
  trunk_head: string;
  guidance: string | null;
}

export function repositoryContext(
  repository: string,
  roots: readonly string[],
): RepositoryContext | null {
  const commonDir = resolveCommonDir(repository);
  if (!commonDir) return null;
  const trunk = resolveTrunk(repository);
  if (runGit(repository, ["show-ref", "--verify", "--quiet", trunk.ref]).code !== 0) return null;
  const trunkWorktree = findTrunkWorktree(repository, trunk);
  if (!trunkWorktree || !pathIsWithin(trunkWorktree.path, roots)) return null;
  const trunkHead = gitValue(repository, ["rev-parse", trunk.ref]);
  if (!trunkHead) return null;
  return {
    common_dir: commonDir,
    trunk,
    trunk_worktree: normalizePath(trunkWorktree.path),
    trunk_head: trunkHead,
    guidance: supervisionGuidance(trunkWorktree.path, commonDir),
  };
}

/**
 * The reason a repository has no trunk the supervisor can name. Unlike the
 * others it is not a mistake to correct in Git — a repository whose trunk is
 * `master`, or an upstream clone nobody integrates into at all, is simply not
 * this supervisor's business until somebody says otherwise — so callers match
 * on it by name to collapse those repositories rather than list them.
 */
export const NO_TRUNK_BRANCH = "no trunk branch";

/**
 * Why `repositoryContext` refused, in the words a human needs to act on.
 *
 * A repository the supervisor cannot place still belongs on the roster, so the
 * reason has to travel with it. Each branch here is a different thing to fix,
 * and a trunk that exists but is checked out nowhere is much the likeliest: an
 * operator moved their one checkout onto a feature branch, and nothing else
 * changed at all.
 */
export function missingTrunkReason(repository: string, roots: readonly string[]): string {
  if (!resolveCommonDir(repository)) return "not a Git repository";
  const trunk = resolveTrunk(repository);
  if (runGit(repository, ["show-ref", "--verify", "--quiet", trunk.ref]).code !== 0) {
    return trunk.configured ? `configured trunk ${trunk.branch} does not exist` : NO_TRUNK_BRANCH;
  }
  const trunkWorktree = findTrunkWorktree(repository, trunk);
  if (!trunkWorktree) return `no worktree has ${trunk.branch} checked out`;
  if (!pathIsWithin(trunkWorktree.path, roots)) {
    return `${trunk.branch} is checked out outside the project roots (${normalizePath(trunkWorktree.path)})`;
  }
  return `${trunk.branch} could not be resolved`;
}

/**
 * A worktree whose HEAD the trunk already contains. Its commits have landed, so
 * the expensive questions — how far ahead, which merge base — are answered
 * already; all that remains is whether anything uncommitted is still sitting
 * there and how far behind it has drifted.
 */
export function inspectSettled(
  record: WorktreeRecord,
  context: RepositoryContext,
): WorktreeIdentity | null {
  if (!record.head) return null;
  const worktree = normalizePath(record.path);
  const status = runGit(worktree, ["status", "--porcelain=v1", "--untracked-files=normal"]);
  if (status.code !== 0) return null;
  const behindText = gitValue(worktree, ["rev-list", "--count", `HEAD..${context.trunk.ref}`]);
  const commitsBehind = behindText === null ? Number.NaN : Number.parseInt(behindText, 10);
  if (!Number.isFinite(commitsBehind)) return null;

  return {
    worktree,
    common_dir: context.common_dir,
    trunk_branch: context.trunk.branch,
    trunk_worktree: context.trunk_worktree,
    guidance: context.guidance,
    branch: record.detached || !record.branch ? null : record.branch.replace(/^refs\/heads\//, ""),
    head: record.head,
    trunk_head: context.trunk_head,
    commits_ahead: 0,
    commits_behind: commitsBehind,
    clean: status.stdout.trim() === "",
  };
}

/** Whether the trunk's remote already contains it, or null with no such ref. */
export function trunkIsPushed(repository: string, trunk: Trunk): boolean | null {
  if (runGit(repository, ["show-ref", "--verify", "--quiet", trunk.remote_ref]).code !== 0) {
    return null;
  }
  return (
    runGit(repository, ["merge-base", "--is-ancestor", trunk.ref, trunk.remote_ref]).code === 0
  );
}

export type RepositoryCandidate = WorktreeIdentity;

export function inspectWorktree(cwd: string, roots: readonly string[]): WorktreeIdentity | null {
  const worktree = gitValue(cwd, ["rev-parse", "--show-toplevel"]);
  const commonDir = resolveCommonDir(cwd);
  if (!worktree || !commonDir) return null;

  const trunk = resolveTrunk(worktree);
  if (runGit(worktree, ["show-ref", "--verify", "--quiet", trunk.ref]).code !== 0) return null;

  const trunkWorktree = findTrunkWorktree(worktree, trunk);
  if (!trunkWorktree || !pathIsWithin(trunkWorktree.path, roots)) return null;

  const head = gitValue(worktree, ["rev-parse", "HEAD"]);
  const trunkHead = gitValue(worktree, ["rev-parse", trunk.ref]);
  const aheadText = gitValue(worktree, ["rev-list", "--count", `${trunk.ref}..HEAD`]);
  const behindText = gitValue(worktree, ["rev-list", "--count", `HEAD..${trunk.ref}`]);
  if (!head || !trunkHead || aheadText === null || behindText === null) return null;

  const commitsAhead = Number.parseInt(aheadText, 10);
  const commitsBehind = Number.parseInt(behindText, 10);
  if (!Number.isFinite(commitsAhead) || !Number.isFinite(commitsBehind)) return null;

  const branch = gitValue(worktree, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
  const status = runGit(worktree, ["status", "--porcelain=v1", "--untracked-files=normal"]);
  if (status.code !== 0) return null;

  return {
    worktree: normalizePath(worktree),
    common_dir: commonDir,
    trunk_branch: trunk.branch,
    trunk_worktree: normalizePath(trunkWorktree.path),
    guidance: supervisionGuidance(trunkWorktree.path, commonDir),
    branch,
    head,
    trunk_head: trunkHead,
    commits_ahead: commitsAhead,
    commits_behind: commitsBehind,
    clean: status.stdout.trim() === "",
  };
}

/**
 * Whether a commit was ever made in this worktree, from its own HEAD reflog.
 *
 * A linked worktree keeps its own log under the repository's `worktrees/<id>/`
 * directory, so this asks what happened *here* rather than what happened to
 * the branch elsewhere. It is the one question Git's commit graph cannot
 * answer: a worktree created an hour ago and a worktree whose work was
 * fast-forwarded into `main` are both contained in `main` and both clean, and
 * only the second is finished work. An unreadable or absent log answers true —
 * unknown history is never grounds for ignoring a worktree.
 */
export function worktreeHasCommits(worktree: string): boolean {
  const result = runGit(worktree, ["reflog", "show", "--format=%gs", "HEAD"]);
  if (result.code !== 0) return true;
  const entries = result.stdout.split("\n").filter((line) => line.trim() !== "");
  if (entries.length === 0) return true;
  return entries.some((entry) => entry.startsWith("commit"));
}
