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
  main_worktree: string;
  branch: string | null;
  head: string;
  main_head: string;
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

export function findMainWorktree(repository: string): WorktreeRecord | null {
  return listWorktrees(repository).find((worktree) => worktree.branch === "refs/heads/main") ?? null;
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

export function inspectCandidate(cwd: string, roots: readonly string[]): RepositoryCandidate | null {
  const repository = inspectWorktree(cwd, roots);
  return repository && repository.commits_ahead > 0 ? repository : null;
}

/**
 * What every worktree of one repository shares: where `main` lives, what it
 * points at, and which common directory registers them all. Resolving this
 * once per scan is what makes surveying settled worktrees affordable — each
 * one then costs a status call and a count instead of a full inspection.
 */
export interface RepositoryContext {
  common_dir: string;
  main_worktree: string;
  main_head: string;
}

export function repositoryContext(
  repository: string,
  roots: readonly string[],
): RepositoryContext | null {
  const commonDir = resolveCommonDir(repository);
  if (!commonDir) return null;
  if (runGit(repository, ["show-ref", "--verify", "--quiet", "refs/heads/main"]).code !== 0) return null;
  const mainWorktree = findMainWorktree(repository);
  if (!mainWorktree || !pathIsWithin(mainWorktree.path, roots)) return null;
  const mainHead = gitValue(repository, ["rev-parse", "refs/heads/main"]);
  if (!mainHead) return null;
  return {
    common_dir: commonDir,
    main_worktree: normalizePath(mainWorktree.path),
    main_head: mainHead,
  };
}

/**
 * The reason a repository names its trunk something other than `main`. It is
 * the one refusal that never becomes actionable, so callers match on it by
 * name rather than by retyping the sentence.
 */
export const NO_MAIN_BRANCH = "no local main branch";

/**
 * Why `repositoryContext` refused, in the words a human needs to act on.
 *
 * A repository the supervisor cannot place still belongs on the roster, so the
 * reason has to travel with it. Each branch here is a different thing to fix,
 * and "no local main checked out" is much the likeliest: an operator moved
 * their one checkout onto a feature branch, and nothing else changed at all.
 */
export function missingMainReason(repository: string, roots: readonly string[]): string {
  if (!resolveCommonDir(repository)) return "not a Git repository";
  if (runGit(repository, ["show-ref", "--verify", "--quiet", "refs/heads/main"]).code !== 0) {
    return NO_MAIN_BRANCH;
  }
  const mainWorktree = findMainWorktree(repository);
  if (!mainWorktree) return "no local main checked out";
  if (!pathIsWithin(mainWorktree.path, roots)) {
    return `main is checked out outside the project roots (${normalizePath(mainWorktree.path)})`;
  }
  return "main could not be resolved";
}

/**
 * A worktree whose HEAD `main` already contains. Its commits have landed, so
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
  const behindText = gitValue(worktree, ["rev-list", "--count", "HEAD..refs/heads/main"]);
  const commitsBehind = behindText === null ? Number.NaN : Number.parseInt(behindText, 10);
  if (!Number.isFinite(commitsBehind)) return null;

  return {
    worktree,
    common_dir: context.common_dir,
    main_worktree: context.main_worktree,
    branch: record.detached || !record.branch ? null : record.branch.replace(/^refs\/heads\//, ""),
    head: record.head,
    main_head: context.main_head,
    commits_ahead: 0,
    commits_behind: commitsBehind,
    clean: status.stdout.trim() === "",
  };
}

/** Whether `origin/main` already contains local `main`, or null with no such ref. */
export function mainIsPushed(repository: string): boolean | null {
  if (runGit(repository, ["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"]).code !== 0) {
    return null;
  }
  return (
    runGit(repository, [
      "merge-base",
      "--is-ancestor",
      "refs/heads/main",
      "refs/remotes/origin/main",
    ]).code === 0
  );
}

export type RepositoryCandidate = WorktreeIdentity;

export function inspectWorktree(cwd: string, roots: readonly string[]): WorktreeIdentity | null {
  const worktree = gitValue(cwd, ["rev-parse", "--show-toplevel"]);
  const commonDir = resolveCommonDir(cwd);
  if (!worktree || !commonDir) return null;

  const mainRef = runGit(worktree, ["show-ref", "--verify", "--quiet", "refs/heads/main"]);
  if (mainRef.code !== 0) return null;

  const mainWorktree = findMainWorktree(worktree);
  if (!mainWorktree || !pathIsWithin(mainWorktree.path, roots)) return null;

  const head = gitValue(worktree, ["rev-parse", "HEAD"]);
  const mainHead = gitValue(worktree, ["rev-parse", "refs/heads/main"]);
  const aheadText = gitValue(worktree, ["rev-list", "--count", "refs/heads/main..HEAD"]);
  const behindText = gitValue(worktree, ["rev-list", "--count", "HEAD..refs/heads/main"]);
  if (!head || !mainHead || aheadText === null || behindText === null) return null;

  const commitsAhead = Number.parseInt(aheadText, 10);
  const commitsBehind = Number.parseInt(behindText, 10);
  if (!Number.isFinite(commitsAhead) || !Number.isFinite(commitsBehind)) return null;

  const branch = gitValue(worktree, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
  const status = runGit(worktree, ["status", "--porcelain=v1", "--untracked-files=normal"]);
  if (status.code !== 0) return null;

  return {
    worktree: normalizePath(worktree),
    common_dir: commonDir,
    main_worktree: normalizePath(mainWorktree.path),
    branch,
    head,
    main_head: mainHead,
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
