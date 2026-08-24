import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { isAbsolute, relative, resolve } from "node:path";
import { realpathSync } from "node:fs";

export interface CommandResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface WorktreeRecord {
  path: string;
  head: string | null;
  branch: string | null;
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
      current = { path: line.slice("worktree ".length), head: null, branch: null };
    } else if (current && line.startsWith("HEAD ")) {
      current.head = line.slice("HEAD ".length);
    } else if (current && line.startsWith("branch ")) {
      current.branch = line.slice("branch ".length);
    }
  }
  if (current) records.push(current);
  return records;
}

export function listWorktrees(repository: string): WorktreeRecord[] {
  const result = runGit(repository, ["worktree", "list", "--porcelain"]);
  return result.code === 0 ? parseWorktrees(result.stdout) : [];
}

export function findMainWorktree(repository: string): WorktreeRecord | null {
  return listWorktrees(repository).find((worktree) => worktree.branch === "refs/heads/main") ?? null;
}

export function resolveCommonDir(cwd: string): string | null {
  const value = gitValue(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  return value ? normalizePath(value) : null;
}

export function inspectCandidate(cwd: string, roots: readonly string[]): RepositoryCandidate | null {
  const repository = inspectWorktree(cwd, roots);
  return repository && repository.commits_ahead > 0 ? repository : null;
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
