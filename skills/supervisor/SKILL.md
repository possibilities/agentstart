---
name: supervisor
description: Run a persistent lifecycle loop for peer worktrees—discover every worktree from Git itself, report a roster of what is watching, landed, and removable at start and stop, obtain exact-commit readiness, fast-forward work into local main, push origin/main, tell the human whenever a worktree becomes clean and removable, and reap it after its agent and workspace close. Use when an agent should supervise peer commits and cleanup continuously.
---

# Supervisor

Keep finished peer work moving from its worktree into local `main` and
`origin/main`. The peer owns a clean, verified commit. You own readiness,
integration, publication, communication, and the final guarded worktree reap.
Never close a session or workspace yourself, and never delete a branch.

Report standing, not just change. A run opens and closes with the full roster,
and no worktree becomes removable without the human hearing it.

## Open with the roster

Resolve this skill's directory, then run `scripts/watch.ts` as a long-lived
process. Its first stdout line is a `roster` object — every worktree under the
project roots, each placed as **watching**, **landed**, or **removable** — and
the same object is available at any time from `scripts/status.ts`, which takes
the same `--project-root` and `--socket` arguments and needs no watcher.

Report that roster to the human as the first thing you do, before working any
candidate. Keep it compact: one line per worktree, grouped by category, naming
the branch, the short head, the live session where there is one, and the
blocker on anything landed that is not removable. Say the counts plainly —
how many are watching, landed, and removable — and say when
`ownership_available` is false, because an unreachable agent development
environment means no session is knowable and a worktree that looks unowned
may not be.

Report the roster again whenever the operator stops the supervisor, and
whenever they ask what you are watching. A run that ends without one has left
its picture in the scrollback.

## Consume the event stream

After the roster, the watcher emits canonical `merge_candidate`,
`unowned_candidate`, `removable_worktree`, and `reap_candidate` JSON objects,
one per stdout line. Both the watcher and `status.ts` default to projects whose
local `main` worktree is under `~/code` or `~/src`; add repeatable
`--project-root <path>` arguments when the operator has other roots.

- In Claude Code, run the watcher through native `Monitor()` so each stdout
  event wakes the session. Re-arm the monitor as its contract requires.
- In Codex, start the watcher as a background process with `--wake-self`. The
  JSONL stdout remains the event record; self-messaging through AgentSurface
  turns each event into a new supervisor turn when background stdout alone
  cannot.
- In another harness, keep the process alive through its native background
  facility and consume stdout incrementally. Poll only to recover a dead
  watcher, never to discover work.

### Two independent sources

Worktrees are found by Git; sessions are found by the agent development
environment. Keeping those separate is what makes the loop complete.

**Git answers which worktrees exist.** Every linked worktree is registered in
its repository's common directory, and `git worktree list --porcelain` marks a
registration `prunable` once its checkout is gone from disk. The watcher walks
the project roots for repositories, then watches each one's worktree registry
and loose refs on the filesystem, rescanning the affected repository when
either changes. A worktree created by an ADE, by a script, or by a person
typing `git worktree add` is discovered identically, whether or not an agent
ever ran there — and a commit made in an existing worktree is noticed the same
way. Discovery holds no opinion about which ADE, if any, is running.

Coming online is itself a full scan. Before any event arrives, the watcher
reports the roster, then every worktree in every project root that already
carries unmerged commits — including ones whose agent committed, quit, and left
days ago — and every worktree whose work has already landed. Expect a burst of
candidates at startup on a machine that has been running without a supervisor,
and work them like any other.

Filesystem watches are the signal; `--sweep-interval <seconds>` (default 300,
`0` disables) is only a backstop for events a watch dropped, which happens on
network and some virtualised filesystems. `--no-discover` turns Git discovery
off entirely and leaves only ADE lifecycle events.

**The ADE answers who is working there.** Herdr is this machine's ADE: the
watcher holds its `events.subscribe` stream, reconciles with `agent.list` on
startup and every reconnect, excludes its own pane, and correlates agent exit
with `workspace.closed`; only both facts produce a reap candidate. It
reconnects by itself. If it exits, diagnose and restart it; do not replace it
with an `agentsurface agents` polling loop. Another ADE would satisfy the same
small contract — name the session working in a given worktree, and report when
a workspace closes — without touching discovery.

A discovered worktree whose commits `main` already contains arrives as a
`removable_worktree` rather than a merge candidate — see below. One that still
carries unmerged commits and whose owner the ADE can name arrives as a
`merge_candidate` with `reason: "discovered"`. One nobody can claim arrives as
an `unowned_candidate`, which is never merged on your own authority: there is
no session to give exact-SHA readiness, so bring it to the human with its
branch, head, and commit count, and let them decide. This is the case the loop
exists to stop losing — an agent that committed and quit leaves real work that
no lifecycle event will ever mention again.

## Qualify a candidate

Maintain a queue keyed by `common_dir`, with only one active candidate per
repository. A candidate is evidence, not permission to merge.

1. Read `clean`, `head`, `main_head`, `worktree`, and `session_id` from the
   event. If the source is dirty, ask the peer to finish or discard its
   uncommitted state first.
2. Message the peer by stable session id, leaving a calling card. A peer
   knows nothing about you: its own guidance stops its work at a commit and
   says nothing about supervisors, so every reach-out carries what it needs
   to answer you. The bus supplies your identity mechanically — it prefixes
   the message with your name, session id, and worktree, which is the address
   the peer replies to — so the card adds only what the prefix cannot: the
   skill to reach back with, the exact reply, and whose job integration is.

   ```sh
   agentsurface message <session-id> "Supervisor here. I found commit <full-sha> in <worktree>. Is that exact commit clean, verified, complete, and ready for me to fast-forward into local main? Load your bus skill and reply to the session named in this message's prefix with exactly READY <full-sha> and nothing else, or tell me what remains. Integration and publication are mine — leave main and the remote alone."
   ```

   Every later message keeps the card: name the exact SHA under discussion,
   and reaffirm the boundary whenever you assign the peer work of its own.

3. Accept only `READY <full-sha>` for the candidate's exact full object id.
   Normal conversation, an earlier approval, a shortened id, or approval for a
   different HEAD is not readiness. A new commit invalidates the old approval.

If the peer declines or still has work, acknowledge it and wait for its next
working-to-idle transition or a proactive exact-SHA readiness reply. Do not
pressure an unfinished result into main.

An `unowned_candidate` has no step 2 and no step 3. Nobody is there to approve
it, and an absent peer is not a silent yes. Report it to the human with its
repository, branch, head, commit count, and cleanliness, and integrate it only
if they tell you to. Keep it out of the per-repository queue so it never blocks
a live peer's work.

## Integrate and push

After exact readiness, run the guarded helper from this skill directory:

```sh
scripts/integrate.ts \
  --source <candidate-worktree> \
  --expected-head <approved-full-sha>
```

Pass the same repeatable `--project-root` arguments used by the watcher when
custom roots apply. The helper revalidates the exact source HEAD and
cleanliness, finds the worktree holding local `main`, fetches `origin/main`,
allows Git to preserve non-overlapping human changes in that main worktree,
fast-forwards only, pushes `main`, and verifies the remote exact SHA. Its one
stdout JSON object is authoritative.

- `integrated_and_pushed`: tell the peer the exact SHA is now local main and
  origin/main. Then advance that repository's queue. Do not close or remove
  anything as part of integration — the worktree you just emptied of unmerged
  work will arrive on the stream as a `removable_worktree`, and that, not the
  integration itself, is what you report to the human.
- `source_head_changed` or `source_not_clean`: ask the peer to finish and
  approve its new exact HEAD.
- `source_needs_reconciliation`: send the peer the reported `main_head` and
  explicitly assign reconciliation in its worktree. It may rebase or otherwise
  resolve there because you have now tasked it with that topology work. Require
  fresh verification, a clean worktree, and a new `READY <sha>` afterward.
- `main_remote_diverged`: stop that repository and bring the divergence to the
  human; never force-push.
- `main_update_refused`, `local_integration_refused`, or
  `main_operation_in_progress`: preserve the local-main worktree exactly as it
  is. Resolve with its human owner or retry after their state changes; never
  stash, discard, or rewrite their work.
- `push_failed` or `push_verification_failed`: the JSON says whether local main
  already contains the commit. Keep responsibility for publication and retry
  safely after refreshing remote state; do not tell the peer it shipped yet.

Collaborate with the peer when reconciliation is ordinary and bounded. Ask the
human only for genuine repository ownership, divergence, or intent decisions.
Continue supervising other repositories while one is waiting.

## Report a removable worktree

A `removable_worktree` says a worktree has nothing left to integrate. It
carries `removable`, `blockers`, and `owner` alongside the usual identity.

Tell the human every time one arrives, and say which of the two it is:

- `removable: true` with empty `blockers` — its commits are in `main`, nothing
  uncommitted is left in it, it is a branch and not `main`, and no session is
  in it. The directory is now the only thing left. Name the path, the branch,
  and the head.
- `removable: false` — say the blocker in the event's own words. A live
  session means "removable once that session closes"; uncommitted changes in a
  worktree nobody is sitting in means real work is about to be lost with the
  directory, and that is the one to raise loudest.

Reporting is the whole of this. A `removable_worktree` is never authority to
remove anything: it observes Git, and Git cannot see whether a human still has
that directory open. Cleanup happens only on a `reap_candidate`, whose two
lifecycle facts are the authorization, or when the human tells you to reap a
specific worktree by name.

## Reap a closed worktree

A `reap_candidate` means Herdr observed the agent session end and the worktree
workspace close. It carries every recorded `{harness, session_id, pane_id}`
association plus the exact worktree, branch, HEAD, workspace, and repository.
It authorizes cleanup of that worktree only; it does not authorize deleting its
branch.

Finish any already-approved integration for the same repository first. Then
run the guarded reaper, repeating `--agent-json` for every entry in the event's
`agents` array:

```sh
scripts/reap.ts \
  --worktree <candidate-worktree> \
  --expected-branch <candidate-branch> \
  --expected-head <candidate-full-sha> \
  --workspace-id <herdr-workspace-id> \
  --agent-json '{"harness":"codex","session_id":"<id>","pane_id":"<id>"}'
```

Pass custom `--project-root` arguments as above. The reaper checks the exact
registered worktree, branch, HEAD, project root, and cleanliness; refuses
`main`; runs ordinary `git worktree remove` without force; verifies the branch
still names the same commit; and writes an append-only audit log at
`~/.local/state/agentstart/supervisor/reaped.jsonl`. Each successful cycle has
`reap_started` and `reaped` JSONL records with the harness/session/pane set,
Herdr workspace, repository common directory, main worktree, removed path,
preserved branch, and HEAD.

- `worktree_reaped`: report the removed path, preserved branch and HEAD, and
  log path. No further cleanup is due.
- `worktree_identity_changed`: wait for a fresh event or investigate; never
  remove a path using stale identity.
- `worktree_not_clean`: preserve it and notify the human that uncommitted state
  remains in a closed workspace. Never add `--force`.
- `reap_log_unavailable`: preserve the worktree until its receipt can be
  recorded.
- `worktree_remove_failed` or `reap_verification_failed`: read the durable log
  and current Git state before retrying. Never delete the directory by hand or
  delete the branch.

Reaping does not imply that the branch was merged. The preserved branch and
receipt are the recovery and later-association contract when its creator has
already quit. Git discovery reports such a worktree as an `unowned_candidate`
while its checkout still exists, so raise that with the human before reaping
rather than letting the commits leave with the workspace.

## Stay in the loop

After every candidate reaches a stable outcome, return to sleeping on the
watcher. The loop has no completion condition of its own; it ends only when the
operator stops the supervisor.

On shutdown, stop only the watcher process you started, then close the same way
you opened: run `scripts/status.ts --occasion stop` with the roots you
supervised and report the full roster — what is still watching, what has
landed, and what is removable. Follow it with the loose ends the roster cannot
show: any approved-but-unpublished exact SHAs, any unowned candidates still
awaiting a human decision, and any emitted reap candidates not yet brought to a
stable outcome.
