---
name: supervisor
description: Run a persistent lifecycle loop for peer worktrees—wait on Herdr events, obtain exact-commit readiness, fast-forward work into local main, push origin/main, and reap clean worktrees after their agent and workspace close. Use when an agent should supervise peer commits and cleanup continuously.
---

# Supervisor

Keep finished peer work moving from its worktree into local `main` and
`origin/main`. The peer owns a clean, verified commit. You own readiness,
integration, publication, communication, and the final guarded worktree reap.
Never close a session or workspace yourself, and never delete a branch.

## Start the event loop

Resolve this skill's directory, then run `scripts/watch.ts` as a long-lived
process. It emits canonical `merge_candidate` and `reap_candidate` JSON
objects, one per stdout line. It defaults to projects whose local `main`
worktree is under `~/code` or `~/src`; add repeatable `--project-root <path>`
arguments when the operator has other roots.

- In Claude Code, run the watcher through native `Monitor()` so each stdout
  event wakes the session. Re-arm the monitor as its contract requires.
- In Codex, start the watcher as a background process with `--wake-self`. The
  JSONL stdout remains the event record; self-messaging through AgentSurface
  turns each event into a new supervisor turn when background stdout alone
  cannot.
- In another harness, keep the process alive through its native background
  facility and consume stdout incrementally. Poll only to recover a dead
  watcher, never to discover work.

The watcher holds Herdr's `events.subscribe` stream, reconciles with
`agent.list` on startup and every reconnect, excludes its own pane, and
discovers arbitrary filesystem worktrees from each peer's cwd and Git common
directory. It also correlates agent exit with `workspace.closed`; only both
facts produce a reap candidate. It reconnects by itself. If it exits, diagnose
and restart it; do not replace it with an `agentsurface agents` polling loop.

## Qualify a candidate

Maintain a queue keyed by `common_dir`, with only one active candidate per
repository. A candidate is evidence, not permission to merge.

1. Read `clean`, `head`, `main_head`, `worktree`, and `session_id` from the
   event. If the source is dirty, ask the peer to finish or discard its
   uncommitted state first.
2. Message the peer by stable session id:

   ```sh
   agentsurface message <session-id> "Supervisor found commit <full-sha> in <worktree>. Is this exact commit clean, verified, complete, and ready for local main? Reply over the bus with exactly READY <full-sha>, or explain what remains."
   ```

3. Accept only `READY <full-sha>` for the candidate's exact full object id.
   Normal conversation, an earlier approval, a shortened id, or approval for a
   different HEAD is not readiness. A new commit invalidates the old approval.

If the peer declines or still has work, acknowledge it and wait for its next
working-to-idle transition or a proactive exact-SHA readiness reply. Do not
pressure an unfinished result into main.

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
  anything as part of integration.
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
already quit.

## Stay in the loop

After every candidate reaches a stable outcome, return to sleeping on the
watcher. The loop has no completion condition of its own; it ends only when the
operator stops the supervisor. On shutdown, stop only the watcher process you
started and report any approved-but-unpublished exact SHAs and any emitted
reap candidates not yet brought to a stable outcome.
