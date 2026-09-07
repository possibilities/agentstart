# Harness preference watcher

Funk is the authored source. The managed `agentstart config watch --notify`
LaunchAgent watches Claude's Stowed `~/.claude/preferences.json` and Codex's
`~/code/funk/config/harnesses/codex.toml`, plus native settings in the default
and registered account homes. It never writes those files, never promotes UI
edits into Funk, and never restarts a harness.

After a 750 ms quiet period it parses the source, checks reserved state keys
and common field types, then publishes a private generated snapshot. A
30-second reconciliation catches missed events, replaced directories, and
sleep/wake. Validation is deliberately limited: it does not replace each
harness's complete schema or validate provider/model availability.

Managed launches read current valid preferences immediately. When an edit is
invalid, missing, or breaks Claude's Stow link, launches retain the last verified
snapshot and print a warning. Without a valid earlier snapshot, invalid input
refuses launch. Missing optional sources remain optional until first configured.
Explicit `AGENTSTART_CLAUDE_CONFIG_SOURCE` / `AGENTSTART_CODEX_CONFIG_SOURCE`
retain strict source handling and bypass the shared cache; explicit Claude
`--settings` retains its existing precedence.

Changes are **ready for the next launch**. Running Codex profiles are snapshots;
Claude's native reload behavior is not a guarantee that every running session
has adopted a change.

## Reviewing local edits

`agentstart config status` shows watcher liveness, the last check, source and
snapshot paths, errors, and fields needing review. `--json` returns the same
information without preference values. `agentstart config apply --notify`
performs one reconciliation; installation uses this command before starting
the watcher. Normal config saves require no installer run.

Drift detection compares the leaf fields authored in Funk with native
`settings.json` / `config.toml` on each reconciliation. Initial differences are
listed as shadowed, quietly. A subsequent change to those native fields that
differs from the authored value becomes a review item. Unauthored fields,
trust records, generated hooks/statusline, and account state are outside that
comparison. Edits that occur and revert between observations cannot be seen.
Alternate native homes register when a managed invocation uses them.

Codex's wrapper additionally captures edits to authored fields in its disposable
profile before deletion. Only fields that changed during that invocation are
captured, so CLI/profile overrides alone do not generate drift. If capture
fails, the wrapper retains that profile and prints its path instead of deleting
potential edits. A killed wrapper may leave a profile that must be inspected
manually.

Review the named native file or private event, then deliberately edit Funk if
the change should persist. Matching the recorded value or removing the authored
field clears its drift. `agentstart config acknowledge` dismisses current
reported differences without changing either source or native preferences;
a later native edit can notify again. Nothing automatically writes tracked
preferences, including acknowledgement and recovery.

## Notifications and private state

Meaningful source changes, new errors/drift, and recovery send grouped macOS
notifications through Funk's `funk-notify`. Initial clean startup,
formatting-only edits, and unchanged issues are quiet. Notifications name
fields and review actions, never preference values. Missing/failed notification
delivery is logged; `config status` remains the review surface. Notification
availability follows the machine's existing Funk/macOS notification setup.

Generated state is under `${XDG_STATE_HOME:-~/.local/state}/agentstart/harness-config`:

- `snapshots/`: content-addressed last-good JSON/TOML copies.
- `events/`: private Codex edit receipts, including values for manual review.
- `homes/`: native account-home registrations.
- `state.json`: baselines, unresolved drift, and handled event references.
- `apply.lock` / `watch.lock`: persistent files with kernel-owned advisory locks.
  Locks release on process exit, including crashes; never delete a live lock file.

Files are mode 0600, directories created as 0700. Snapshots and events are kept
for manual review rather than aged out automatically. Do not commit this
state. Corrupt state/events are retained and reported, never silently discarded.
The service logs to `~/.local/state/agentstart/config-watch.log`. It is installed
and supervised by the existing `scripts/install.sh --install` contract as
`io.arthack.agentstart.watch-config`; no second installer or preference sync
owner exists.
