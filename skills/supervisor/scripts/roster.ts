import type { WorktreeIdentity } from "./git.ts";
import { mainIsPushed, normalizePath } from "./git.ts";
import type { OwnershipProvider, WorktreeOwner } from "./ade.ts";
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

export type RosterCategory = "main" | "watching" | "landed" | "removable";

export interface RosterWorktree extends WorktreeIdentity {
  category: RosterCategory;
  owner: WorktreeOwner | null;
  removable: boolean;
  /** Why a landed worktree is not removable; empty when it is. */
  blockers: string[];
}

export interface RosterRepository {
  repository: string;
  common_dir: string;
  main_worktree: string;
  main_head: string;
  /** Whether `origin/main` already contains local `main`; null with no such ref. */
  main_pushed: boolean | null;
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
  counts: { watching: number; landed: number; removable: number };
  repositories: RosterRepository[];
}

/**
 * Where one surveyed worktree belongs, and what stands between it and removal.
 *
 * Removable means exactly this: its commits are in `main`, nothing uncommitted
 * is left in it, it is a branch and not `main` itself, and no agent is still
 * sitting in it. Anything short of that is a blocker with a name, because a
 * human reading the roster deserves the reason and not just the verdict.
 */
export function place(worktree: DiscoveredWorktree, owner: WorktreeOwner | null): RosterWorktree {
  const blockers: string[] = [];
  if (worktree.state === "main") {
    return { ...identity(worktree), category: "main", owner, removable: false, blockers };
  }
  if (worktree.state === "unmerged") {
    blockers.push(`${worktree.commits_ahead} commit(s) not in main`);
  }
  if (!worktree.clean) blockers.push("uncommitted changes");
  if (worktree.branch === null) blockers.push("detached HEAD");
  if (owner) blockers.push(`session live (${owner.harness ?? "agent"} ${owner.session_id})`);

  const removable = worktree.state === "landed" && blockers.length === 0;
  const category: RosterCategory =
    worktree.state === "unmerged" || owner ? "watching" : removable ? "removable" : "landed";
  return { ...identity(worktree), category, owner, removable, blockers };
}

function identity(worktree: DiscoveredWorktree): WorktreeIdentity {
  const { repository: _repository, state: _state, ...rest } = worktree;
  return rest;
}

export async function buildRoster(
  roots: readonly string[],
  ownership: OwnershipProvider | null,
  occasion: string,
): Promise<Roster> {
  const repositories: RosterRepository[] = [];
  const counts = { watching: 0, landed: 0, removable: 0 };

  for (const repository of findRepositories(roots)) {
    const surveyed = surveyRepository(repository, roots);
    if (surveyed.length === 0) continue;
    const worktrees: RosterWorktree[] = [];
    for (const worktree of surveyed) {
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
