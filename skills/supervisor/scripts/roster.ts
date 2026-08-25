import type { WorktreeIdentity } from "./git.ts";
import {
  isPrimaryWorktree,
  listLiveWorktrees,
  missingTrunkReason,
  NO_TRUNK_BRANCH,
  normalizePath,
  repositoryContext,
  resolveCommonDir,
  resolveTrunk,
  runGit,
  supervisionGuidance,
  trunkIsPushed,
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
  | "trunk"
  | "watching"
  | "quiet"
  | "landed"
  | "removable"
  | "unsupervised";

/**
 * A worktree the supervisor could not place at all keeps the identity fields
 * Git answers without a trunk to compare against — its path, its branch, its
 * head, whether anything is uncommitted — and nulls the rest. A null there is
 * the honest answer: there is no trunk for it to be ahead of.
 */
export interface RosterWorktree
  extends Omit<
    WorktreeIdentity,
    "trunk_branch" | "trunk_worktree" | "trunk_head" | "guidance" | "commits_ahead" | "commits_behind"
  > {
  trunk_branch: string | null;
  trunk_worktree: string | null;
  trunk_head: string | null;
  guidance: string | null;
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
  /** The branch this repository integrates into; null when none was resolved. */
  trunk_branch: string | null;
  /** Where the trunk is checked out; null when nowhere under the roots is. */
  trunk_worktree: string | null;
  trunk_head: string | null;
  /** The remote the trunk publishes to, from its own upstream. */
  trunk_remote: string | null;
  /** Whether the trunk's remote already contains it; null with no such ref. */
  trunk_pushed: boolean | null;
  /**
   * This repository's own supervision instructions, when it keeps a
   * `SUPERVISE.md`. Read it before deciding anything here: it is the only
   * place a repository can say that its branches do not mean what branches
   * usually mean.
   */
  guidance: string | null;
  /** Why nothing in this repository can be supervised; empty when it can be. */
  blockers: string[];
  /**
   * How many worktrees the repository has, whether or not they are listed
   * below. A collapsed repository still says how much it is standing for, so
   * shortening the roster never costs the reader a number.
   */
  worktree_count: number;
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
 * Removable means exactly this: work was done here, its commits are in the
 * trunk, nothing uncommitted is left in it, it is a branch and not the trunk
 * itself, and no agent is still sitting in it. Anything short of that is a
 * blocker with a name, because a human reading the roster deserves the reason
 * and not just the verdict.
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
 * only the worktree that holds the trunk protects it just until an operator
 * switches branches. It is never quiet either, because a permanent blocker
 * that nobody is shown is the same as no blocker at all.
 */
export function place(worktree: DiscoveredWorktree, owner: WorktreeOwner | null): RosterWorktree {
  const blockers: string[] = [];
  if (worktree.state === "trunk") {
    return { ...identity(worktree), category: "trunk", owner, removable: false, blockers };
  }
  const primary = isPrimaryWorktree(worktree.worktree, worktree.common_dir);
  if (primary) blockers.push("the repository's primary checkout");
  if (worktree.state === "unmerged") {
    blockers.push(`${worktree.commits_ahead} commit(s) not in ${worktree.trunk_branch}`);
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
 * A repository whose trunk the supervisor cannot resolve, on the roster anyway.
 *
 * Nothing here can be integrated and nothing here can be reaped, because both
 * are defined against a trunk that is not there. What must not happen is the
 * repository disappearing: its checkouts still exist, work still happens in
 * them, and a roster that omits them prints counts a human reads as coverage.
 * Dropped and clean have to look different, so every worktree Git still lists
 * is reported as unsupervised, carrying the reason and nothing it cannot know.
 */
function unsupervisable(repository: string, roots: readonly string[]): RosterRepository {
  const home = normalizePath(repository);
  const commonDir = resolveCommonDir(repository) ?? home;
  const blocker = missingTrunkReason(repository, roots);
  const records = listLiveWorktrees(repository);

  // A repository with no trunk branch at all is not a supervisable one that
  // went wrong; it is a project nobody has told the supervisor how to
  // integrate, and until somebody does it never will be. Enumerating its every
  // worktree on every roster spends lines on a condition that will never
  // change, and the rows that do mean something — the repository whose one
  // checkout moved onto a feature branch this afternoon — get buried among
  // them. The repository still appears, still carries its reason, and still
  // says how many worktrees it stands for; only the per-worktree rows are
  // withheld, and only for the permanent case.
  if (blocker === NO_TRUNK_BRANCH) {
    return {
      repository: home,
      common_dir: commonDir,
      trunk_branch: null,
      trunk_worktree: null,
      trunk_head: null,
      trunk_remote: null,
      trunk_pushed: null,
      guidance: supervisionGuidance(home, commonDir),
      blockers: [blocker],
      worktree_count: records.length,
      worktrees: [],
    };
  }

  const worktrees = records.map((record): RosterWorktree => {
    const worktree = normalizePath(record.path);
    const status = runGit(worktree, ["status", "--porcelain=v1", "--untracked-files=normal"]);
    return {
      worktree,
      common_dir: commonDir,
      trunk_branch: null,
      trunk_worktree: null,
      guidance: null,
      branch: record.detached || !record.branch ? null : record.branch.replace(/^refs\/heads\//, ""),
      head: record.head ?? "",
      trunk_head: null,
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
    trunk_branch: null,
    trunk_worktree: null,
    trunk_head: null,
    trunk_remote: null,
    trunk_pushed: null,
    guidance: supervisionGuidance(home, commonDir),
    blockers: [blocker],
    worktree_count: worktrees.length,
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
      counts.unsupervised += unplaceable.worktree_count;
      repositories.push(unplaceable);
      continue;
    }
    const surveyed = surveyRepository(repository, roots);
    if (surveyed.length === 0) continue;
    const worktrees: RosterWorktree[] = [];
    for (const worktree of surveyed) {
      if (worktree.state !== "trunk" && !worktree.worked) continue;
      const owner = ownership ? await ownership.owner(worktree.worktree) : null;
      const placed = place(worktree, owner);
      if (placed.category !== "trunk") counts[placed.category] += 1;
      worktrees.push(placed);
    }
    const first = surveyed[0];
    if (!first) continue;
    const trunk = resolveTrunk(repository);
    repositories.push({
      repository: normalizePath(repository),
      common_dir: first.common_dir,
      trunk_branch: first.trunk_branch,
      trunk_worktree: first.trunk_worktree,
      trunk_head: first.trunk_head,
      trunk_remote: trunk.remote,
      trunk_pushed: trunkIsPushed(repository, trunk),
      guidance: first.guidance,
      blockers: [],
      worktree_count: worktrees.length,
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
