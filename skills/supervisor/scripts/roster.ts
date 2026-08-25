import type { WorktreeIdentity } from "./git.ts";
import {
  isPrimaryWorktree,
  listLiveWorktrees,
  mainIsPushed,
  missingMainReason,
  normalizePath,
  repositoryContext,
  resolveCommonDir,
  runGit,
} from "./git.ts";
import { describeSession, type OwnershipProvider, type WorktreeOwner } from "./ade.ts";
import { type DiscoveredWorktree, findRepositories, surveyRepository } from "./worktrees.ts";

/**
 * The roster: everything the supervisor is watching, in one object.
 *
 * The stream reports change; this reports standing. It exists so a supervisor
 * can open and close its run with the whole picture — which worktrees still
 * hold work, which have landed, and which are now nothing but a directory
 * waiting to be removed — instead of leaving that knowledge in the scrollback
 * of whichever events happened to fire.
 */

export type RosterCategory =
  | "main"
  | "watching"
  | "quiet"
  | "landed"
  | "removable"
  | "unsupervised";

/**
 * A worktree the supervisor could not place at all keeps the identity fields
 * Git answers without a `main` to compare against — its path, its branch, its
 * head, whether anything is uncommitted — and nulls the rest. A null there is
 * the honest answer: there is no `main` for it to be ahead of.
 */
export interface RosterWorktree
  extends Omit<WorktreeIdentity, "main_worktree" | "main_head" | "commits_ahead" | "commits_behind"> {
  main_worktree: string | null;
  main_head: string | null;
  commits_ahead: number | null;
  commits_behind: number | null;
  category: RosterCategory;
  owner: WorktreeOwner | null;
  removable: boolean;
  /** Why a landed worktree is not removable; empty when it is. */
  blockers: string[];
}

export interface RosterRepository {
  repository: string;
  common_dir: string;
  /** Where `main` is checked out; null when nowhere under the roots is. */
  main_worktree: string | null;
  main_head: string | null;
  /** Whether `origin/main` already contains local `main`; null with no such ref. */
  main_pushed: boolean | null;
  /** Why nothing in this repository can be supervised; empty when it can be. */
  blockers: string[];
  worktrees: RosterWorktree[];
}

export interface Roster {
  schema_version: 1;
  type: "roster";
  occasion: string;
  generated_at: string;
  project_roots: string[];
  /** Whether an agent development environment answered; false means no session is knowable. */
  ownership_available: boolean;
  counts: {
    watching: number;
    quiet: number;
    landed: number;
    removable: number;
    unsupervised: number;
  };
  repositories: RosterRepository[];
}

/**
 * Where one surveyed worktree belongs, and what stands between it and removal.
 *
 * Removable means exactly this: work was done here, its commits are in `main`,
 * nothing uncommitted is left in it, it is a branch and not `main` itself, and
 * no agent is still sitting in it. Anything short of that is a blocker with a
 * name, because a human reading the roster deserves the reason and not just
 * the verdict.
 *
 * Quiet is the absence of all of it: a landed, clean worktree whose agent has
 * not left yet. It holds nothing for the supervisor, and a roster that spends
 * a line on each of them buries the ones that do.
 *
 * A worktree where no work was ever done is not placed at all. Discovery
 * already refuses to raise an event for one, on the reasoning that a checkout
 * somebody opened is not work; counting it here would contradict that and
 * would inflate quiet with directories the supervisor has no business in. Its
 * first commit — or any uncommitted change, which discovery already treats as
 * work — brings it into the picture like any other.
 *
 * The repository's primary checkout is the one blocker that never clears. It
 * is a person's working directory rather than a worktree somebody added for a
 * task, and which branch it happens to hold says nothing about that — refusing
 * only the worktree that holds `main` protects it just until an operator
 * switches branches. It is never quiet either, because a permanent blocker
 * that nobody is shown is the same as no blocker at all.
 */
export function place(worktree: DiscoveredWorktree, owner: WorktreeOwner | null): RosterWorktree {
  const blockers: string[] = [];
  if (worktree.state === "main") {
    return { ...identity(worktree), category: "main", owner, removable: false, blockers };
  }
  const primary = isPrimaryWorktree(worktree.worktree, worktree.common_dir);
  if (primary) blockers.push("the repository's primary checkout");
  if (worktree.state === "unmerged") {
    blockers.push(`${worktree.commits_ahead} commit(s) not in main`);
  }
  if (!worktree.clean) blockers.push("uncommitted changes");
  if (worktree.branch === null) blockers.push("detached HEAD");
  if (owner) blockers.push(`session live (${describeSession(owner)})`);

  const removable = worktree.state === "landed" && worktree.worked && blockers.length === 0;
  const quiet = !primary && worktree.state === "landed" && worktree.clean && owner !== null;
  const category: RosterCategory = quiet
    ? "quiet"
    : worktree.state === "unmerged" || owner
      ? "watching"
      : removable
        ? "removable"
        : "landed";
  return { ...identity(worktree), category, owner, removable, blockers };
}

/**
 * A repository whose `main` the supervisor cannot resolve, on the roster
 * anyway.
 *
 * Nothing here can be integrated and nothing here can be reaped, because both
 * are defined against a `main` that is not there. What must not happen is the
 * repository disappearing: its checkouts still exist, work still happens in
 * them, and a roster that omits them prints counts a human reads as coverage.
 * Dropped and clean have to look different, so every worktree Git still lists
 * is reported as unsupervised, carrying the reason and nothing it cannot know.
 */
function unsupervisable(repository: string, roots: readonly string[]): RosterRepository {
  const home = normalizePath(repository);
  const commonDir = resolveCommonDir(repository) ?? home;
  const blocker = missingMainReason(repository, roots);
  const worktrees = listLiveWorktrees(repository).map((record): RosterWorktree => {
    const worktree = normalizePath(record.path);
    const status = runGit(worktree, ["status", "--porcelain=v1", "--untracked-files=normal"]);
    return {
      worktree,
      common_dir: commonDir,
      main_worktree: null,
      branch: record.detached || !record.branch ? null : record.branch.replace(/^refs\/heads\//, ""),
      head: record.head ?? "",
      main_head: null,
      commits_ahead: null,
      commits_behind: null,
      // An unreadable status is not a clean one; nothing about this repository
      // is being trusted enough to delete anything, but the roster still says
      // what it saw.
      clean: status.code === 0 && status.stdout.trim() === "",
      category: "unsupervised",
      owner: null,
      removable: false,
      blockers: [blocker],
    };
  });
  return {
    repository: home,
    common_dir: commonDir,
    main_worktree: null,
    main_head: null,
    main_pushed: null,
    blockers: [blocker],
    worktrees,
  };
}

function identity(worktree: DiscoveredWorktree): WorktreeIdentity {
  const { repository: _repository, state: _state, worked: _worked, ...rest } = worktree;
  return rest;
}

export async function buildRoster(
  roots: readonly string[],
  ownership: OwnershipProvider | null,
  occasion: string,
): Promise<Roster> {
  const repositories: RosterRepository[] = [];
  const counts = { watching: 0, quiet: 0, landed: 0, removable: 0, unsupervised: 0 };

  for (const repository of findRepositories(roots)) {
    // Ask first whether this repository can be supervised at all, because the
    // survey answers "cannot" and "nothing to report" with the same empty
    // array, and a roster that cannot tell them apart drops repositories
    // without saying so.
    if (!repositoryContext(repository, roots)) {
      const unplaceable = unsupervisable(repository, roots);
      counts.unsupervised += unplaceable.worktrees.length;
      repositories.push(unplaceable);
      continue;
    }
    const surveyed = surveyRepository(repository, roots);
    if (surveyed.length === 0) continue;
    const worktrees: RosterWorktree[] = [];
    for (const worktree of surveyed) {
      if (worktree.state !== "main" && !worktree.worked) continue;
      const owner = ownership ? await ownership.owner(worktree.worktree) : null;
      const placed = place(worktree, owner);
      if (placed.category !== "main") counts[placed.category] += 1;
      worktrees.push(placed);
    }
    const first = surveyed[0];
    if (!first) continue;
    repositories.push({
      repository: normalizePath(repository),
      common_dir: first.common_dir,
      main_worktree: first.main_worktree,
      main_head: first.main_head,
      main_pushed: mainIsPushed(repository),
      blockers: [],
      worktrees,
    });
  }

  // An ADE that cannot be reached is not the same as one reporting nobody
  // home: the first means ownership is unknown, and the roster says so rather
  // than letting every worktree read as unowned and therefore removable.
  const available = ownership ? ((await ownership.available?.()) ?? true) : false;

  return {
    schema_version: 1,
    type: "roster",
    occasion,
    generated_at: new Date().toISOString(),
    project_roots: roots.map(normalizePath),
    ownership_available: available,
    counts,
    repositories,
  };
}
