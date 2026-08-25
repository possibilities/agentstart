import { readdirSync, statSync, watch } from "node:fs";
import type { FSWatcher } from "node:fs";
import { join } from "node:path";
import {
  type WorktreeIdentity,
  inspectCandidate,
  inspectSettled,
  isPrimaryWorktree,
  listLiveWorktrees,
  normalizePath,
  pathIsWithin,
  repositoryContext,
  resolveCommonDir,
  runGit,
  worktreeHasCommits,
} from "./git.ts";

/**
 * Git-native worktree discovery.
 *
 * Every linked worktree is registered in its repository's common directory
 * under `worktrees/`, and `git worktree list --porcelain` reports each
 * registration along with a `prunable` marker when its checkout no longer
 * exists on disk. That registry — not any multiplexer, session manager, or
 * agent lifecycle event — is the authority on which worktrees exist. This
 * module watches the registry directly, so a worktree created by hand, by a
 * script, or by any tool at all is discovered identically.
 */

/** Directory names never worth descending into while looking for repositories. */
const SKIP_DIRECTORIES = new Set([
  "node_modules",
  "target",
  "vendor",
  "dist",
  "build",
  ".venv",
  "venv",
  "Library",
]);

/** How deep below a project root a repository may sit before it is ignored. */
const MAX_REPOSITORY_DEPTH = 3;

/** Coalescing window for the burst of filesystem events one Git command emits. */
const REPOSITORY_DEBOUNCE_MS = 750;

/** Coalescing window for project-root changes, which re-enumerate repositories. */
const ROOT_DEBOUNCE_MS = 2_000;

/**
 * Where a worktree stands against its repository's trunk.
 *
 * `trunk` is the integration target itself. `unmerged` carries commits the
 * trunk does not, and is the supervisor's work. `landed` has nothing left to
 * integrate — which is the state a finished worktree ends in, and the reason
 * discovery reports it rather than dropping it: a landed worktree is where
 * removability is decided.
 */
export type WorktreeState = "trunk" | "unmerged" | "landed";

export interface DiscoveredWorktree extends WorktreeIdentity {
  /** Absolute path of the repository whose registry produced this worktree. */
  repository: string;
  state: WorktreeState;
  /**
   * Whether any work was ever done here — a commit made in this worktree, or
   * uncommitted changes sitting in it now. A worktree that has neither is a
   * checkout somebody opened, not work the supervisor has any business with.
   */
  worked: boolean;
}

export interface DiscoveryOptions {
  projectRoots: readonly string[];
  /**
   * Seconds between safety sweeps of every known repository. Filesystem
   * watches are the primary signal; a sweep only recovers events a watch
   * dropped, which happens on network and some virtualised filesystems. Zero
   * disables sweeping entirely and makes discovery purely event-driven.
   */
  sweepIntervalSeconds: number;
  /**
   * Returning `false` says the worktree was not reported, which un-marks it so
   * a later scan reconsiders the same situation. A worktree the supervisor
   * ignores today — nobody has done any work in it, or the agent that did is
   * still sitting there — becomes reportable when its ownership changes, and
   * ownership is not something Git's registry ever moves.
   */
  onWorktree(worktree: DiscoveredWorktree): void | boolean | Promise<void | boolean>;
  onDiagnostic?(message: string): void;
}

/** Repositories whose trunk worktree sits inside one of the project roots. */
export function findRepositories(roots: readonly string[]): string[] {
  const found = new Set<string>();
  for (const root of roots) descend(normalizePath(root), 0, found);
  return oneEntryPointPerRepository(found);
}

/**
 * One entry point per repository, not one per checkout.
 *
 * Two checkouts of the same repository can both sit directly under a project
 * root — a primary checkout beside a dedicated trunk worktree is the ordinary
 * reason — and they share a common directory, so surveying both lists and
 * counts every worktree of that repository twice. The common directory is what
 * identifies a repository; a path only identifies a window onto one.
 *
 * The primary checkout wins the tie where there is one, because it is the path
 * that names the repository itself. Nothing downstream depends on the choice:
 * every question the survey asks — which worktrees are registered, where the trunk
 * is checked out, what it points at — is answered for the whole repository from
 * any of its worktrees.
 */
function oneEntryPointPerRepository(found: Set<string>): string[] {
  const byRepository = new Map<string, string>();
  const unresolved: string[] = [];

  for (const path of [...found].sort()) {
    const commonDir = resolveCommonDir(path);
    // A directory holding `.git` that Git will not answer for is not a
    // repository at all. Keep it rather than guess which repository it belongs
    // to: it costs one survey that finds nothing.
    if (!commonDir) {
      unresolved.push(path);
      continue;
    }
    const chosen = byRepository.get(commonDir);
    if (chosen === undefined || isPrimaryWorktree(path, commonDir)) byRepository.set(commonDir, path);
  }
  return [...byRepository.values(), ...unresolved].sort();
}

function descend(directory: string, depth: number, found: Set<string>): void {
  let entries: ReturnType<typeof readdirSync>;
  try {
    entries = readdirSync(directory, { withFileTypes: true });
  } catch {
    return;
  }

  // A directory holding `.git` is a checkout; its own subdirectories cannot
  // hold a separate repository worth reporting, so stop descending here.
  if (entries.some((entry) => entry.name === ".git")) {
    found.add(directory);
    return;
  }
  if (depth >= MAX_REPOSITORY_DEPTH) return;

  for (const entry of entries) {
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
    if (entry.name.startsWith(".") || SKIP_DIRECTORIES.has(entry.name)) continue;
    descend(join(directory, entry.name), depth + 1, found);
  }
}

/**
 * Every worktree of `repository` that is registered and present on disk, each
 * placed against its trunk.
 *
 * A worktree whose HEAD the trunk already contains is landed, not uninteresting:
 * it is exactly the set that becomes removable, so it is surveyed cheaply
 * rather than skipped. The expensive inspection is reserved for worktrees that
 * really do carry unmerged commits.
 */
export function surveyRepository(
  repository: string,
  roots: readonly string[],
): DiscoveredWorktree[] {
  const surveyed: DiscoveredWorktree[] = [];

  // One resolution for the whole repository: with no trunk checked out there
  // is nothing to integrate into, and inspecting each of its worktrees is
  // waste.
  // An empty survey is not the same as a clean one, which is why the roster
  // asks `repositoryContext` itself rather than reading silence here as
  // "nothing to report" — see `unsupervisable` in roster.ts.
  const context = repositoryContext(repository, roots);
  if (!context) return surveyed;
  const home = normalizePath(repository);

  for (const record of listLiveWorktrees(repository)) {
    // Settle the common case with one Git call. On a machine with many
    // finished worktrees nearly all of them are already contained in the trunk,
    // and a contained HEAD needs only a status and a count — not the ten calls
    // a full inspection costs. Anything but a definite "yes, contained" falls
    // through to the real inspection.
    const contained =
      record.head !== null &&
      runGit(repository, ["merge-base", "--is-ancestor", record.head, context.trunk.ref]).code === 0;

    if (contained) {
      const identity = inspectSettled(record, context);
      if (!identity) continue;
      const state: WorktreeState =
        normalizePath(record.path) === context.trunk_worktree ? "trunk" : "landed";
      // The reflog is read only where its answer changes anything: a clean,
      // landed worktree is the one place where "finished" and "never started"
      // look identical to the commit graph.
      const worked = state === "trunk" || !identity.clean || worktreeHasCommits(identity.worktree);
      surveyed.push({ ...identity, repository: home, state, worked });
      continue;
    }

    const identity = inspectCandidate(record.path, roots);
    if (identity) surveyed.push({ ...identity, repository: home, state: "unmerged", worked: true });
  }
  return surveyed;
}

/**
 * Every worktree of `repository` carrying commits its trunk does not — the
 * survey narrowed to what the supervisor can actually integrate.
 */
export function scanRepository(
  repository: string,
  roots: readonly string[],
): DiscoveredWorktree[] {
  return surveyRepository(repository, roots).filter((worktree) => worktree.state === "unmerged");
}

export class WorktreeDiscovery {
  private readonly options: DiscoveryOptions;
  private readonly roots: string[];
  private readonly watchers = new Map<string, FSWatcher[]>();
  private readonly rootWatchers: FSWatcher[] = [];
  private readonly timers = new Map<string, ReturnType<typeof setTimeout>>();
  private readonly announced = new Map<string, string>();
  private readonly pending = new Set<string>();
  private sweepTimer: ReturnType<typeof setInterval> | null = null;
  private rootTimer: ReturnType<typeof setTimeout> | null = null;
  private drainTimer: ReturnType<typeof setTimeout> | null = null;
  private stopped = false;

  constructor(options: DiscoveryOptions) {
    this.options = options;
    this.roots = options.projectRoots.map(normalizePath);
  }

  start(): void {
    for (const root of this.roots) this.watchRoot(root);
    this.refreshRepositories();
    const interval = this.options.sweepIntervalSeconds;
    if (interval > 0) {
      this.sweepTimer = setInterval(() => this.sweep(), interval * 1_000);
      this.sweepTimer.unref?.();
    }
  }

  stop(): void {
    this.stopped = true;
    if (this.sweepTimer) clearInterval(this.sweepTimer);
    if (this.rootTimer) clearTimeout(this.rootTimer);
    if (this.drainTimer) clearTimeout(this.drainTimer);
    this.sweepTimer = null;
    this.rootTimer = null;
    this.drainTimer = null;
    this.pending.clear();
    for (const timer of this.timers.values()) clearTimeout(timer);
    this.timers.clear();
    for (const watchers of this.watchers.values()) for (const watcher of watchers) watcher.close();
    this.watchers.clear();
    for (const watcher of this.rootWatchers.splice(0)) watcher.close();
  }

  /** Rescan every known repository, ignoring watches entirely. */
  sweep(): void {
    for (const repository of this.watchers.keys()) this.enqueue(repository);
  }

  /** Scan every queued repository now, blocking until the queue is empty. */
  drainNow(): void {
    while (this.pending.size > 0) {
      const [repository] = this.pending;
      if (repository === undefined) break;
      this.pending.delete(repository);
      this.rescan(repository);
    }
  }

  /**
   * Scanning a repository spawns Git several times, so a machine with dozens of
   * them would block the event loop for many seconds if scanned in one pass —
   * long enough to delay the ADE connection and the watches themselves. One
   * repository per turn of the loop keeps startup responsive.
   */
  private enqueue(repository: string): void {
    if (this.stopped) return;
    this.pending.add(repository);
    if (this.drainTimer) return;
    const drain = () => {
      this.drainTimer = null;
      if (this.stopped) return;
      const [next] = this.pending;
      if (next === undefined) return;
      this.pending.delete(next);
      this.rescan(next);
      if (this.pending.size > 0) {
        this.drainTimer = setTimeout(drain, 0);
        this.drainTimer.unref?.();
      }
    };
    this.drainTimer = setTimeout(drain, 0);
    this.drainTimer.unref?.();
  }

  private refreshRepositories(): void {
    if (this.stopped) return;
    const repositories = findRepositories(this.roots);
    const live = new Set(repositories);
    for (const [repository, watchers] of this.watchers) {
      if (live.has(repository)) continue;
      for (const watcher of watchers) watcher.close();
      this.watchers.delete(repository);
    }
    for (const repository of repositories) {
      if (this.watchers.has(repository)) continue;
      this.watchRepository(repository);
      this.enqueue(repository);
    }
  }

  private watchRoot(root: string): void {
    const watcher = this.observe(root, false, () => {
      if (this.rootTimer) clearTimeout(this.rootTimer);
      this.rootTimer = setTimeout(() => this.refreshRepositories(), ROOT_DEBOUNCE_MS);
      this.rootTimer.unref?.();
    });
    if (watcher) this.rootWatchers.push(watcher);
  }

  private watchRepository(repository: string): void {
    const commonDir = resolveCommonDir(repository);
    if (!commonDir) return;
    const schedule = () => this.schedule(repository);
    const watchers: FSWatcher[] = [];

    // The common directory itself: catches `worktrees/` being created for a
    // repository that has none yet, and `packed-refs` being rewritten.
    const common = this.observe(commonDir, false, schedule);
    if (common) watchers.push(common);

    // The registry: one subdirectory per linked worktree, and each worktree's
    // own HEAD, index, and logs live inside it, so this one recursive watch
    // reports both new worktrees and commits made in existing ones.
    const registry = this.observe(join(commonDir, "worktrees"), true, schedule);
    if (registry) watchers.push(registry);

    // Loose branch refs, which move when any worktree of this repository
    // commits, including the trunk worktree merging work in.
    const heads = this.observe(join(commonDir, "refs", "heads"), true, schedule);
    if (heads) watchers.push(heads);

    this.watchers.set(repository, watchers);
  }

  private observe(path: string, recursive: boolean, onChange: () => void): FSWatcher | null {
    try {
      if (!statSync(path).isDirectory()) return null;
      const watcher = watch(path, { recursive, persistent: false }, () => {
        if (!this.stopped) onChange();
      });
      watcher.on("error", (error) => {
        this.diagnostic(`watch failed for ${path}: ${error.message}`);
        watcher.close();
      });
      return watcher;
    } catch {
      // A repository with no linked worktrees has no registry directory yet;
      // the common-directory watch reports it the moment one appears.
      return null;
    }
  }

  private schedule(repository: string): void {
    if (this.stopped) return;
    const existing = this.timers.get(repository);
    if (existing) clearTimeout(existing);
    const timer = setTimeout(() => {
      this.timers.delete(repository);
      this.enqueue(repository);
    }, REPOSITORY_DEBOUNCE_MS);
    timer.unref?.();
    this.timers.set(repository, timer);
  }

  private rescan(repository: string): void {
    if (this.stopped) return;

    // A registry that has just gained its first worktree needs its watch
    // installed now; `watchRepository` is idempotent per repository.
    const watchers = this.watchers.get(repository);
    if (watchers && watchers.length < 3) {
      for (const watcher of watchers) watcher.close();
      this.watchRepository(repository);
    }

    for (const worktree of surveyRepository(repository, this.roots)) {
      // A worktree can change what it deserves without changing its HEAD: the
      // supervisor fast-forwards the trunk past it and the very same commit turns
      // from unmerged work into a removable checkout. Keying the announcement
      // on the whole situation, not the commit, is what lets that be reported.
      const situation = `${worktree.state}:${worktree.head}:${worktree.clean}`;
      if (this.announced.get(worktree.worktree) === situation) continue;
      this.announced.set(worktree.worktree, situation);
      const path = worktree.worktree;
      void Promise.resolve(this.options.onWorktree(worktree)).then((reported) => {
        if (reported === false && this.announced.get(path) === situation) this.announced.delete(path);
      });
    }
  }

  private diagnostic(message: string): void {
    this.options.onDiagnostic?.(message);
  }
}

export { pathIsWithin };
