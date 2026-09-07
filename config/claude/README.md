# Claude preferences and workspace trust

Funk's `claude` Stow package links its authored preferences to
`~/.claude/preferences.json`. AgentStart's managed Claude shim invokes
`scripts/claude-invocation <native-claude> ...`, which loads that file with
native `--settings` and records workspace trust before replacing itself with
the stock Claude binary. No Claude patch or alternate config home is needed.

The overlay takes precedence over user/project/local settings. An explicit
`--settings` replaces the overlay; individual native CLI flags and managed
policy retain native precedence. UI edits go to Claude's writable settings;
promote desired changes into Funk deliberately. Hooks, statusline installation,
generated auto-mode context, credentials, and account/project history remain
in the existing local files. Do not Stow `settings.json` or `.claude.json`.

Trust is persistent **local** state: the helper sets only
`projects[path].hasTrustDialogAccepted` for the physical cwd, the Git root,
and the main repository when launched from a worktree. This enables trusted
project instructions and hooks; it does not select a different permission
mode or skip tool approvals. It cooperates with Claude's `<config>.lock`
directory mutex, re-reads under lock, preserves unrelated fields, and publishes
atomically. A busy lock times out without being stolen. Malformed JSON or a
symlinked native state file refuses launch without overwriting it.

`CLAUDE_CONFIG_DIR` account homes and their legacy `.config.json` are honored.
The default state path is `~/.claude.json`; custom OAuth layouts require a
native bypass. An absent optional preferences file initially passes through unchanged;
a missing/invalid default file later uses its verified last-good snapshot.
An explicitly selected missing file fails. The source can be overridden with
`AGENTSTART_CLAUDE_CONFIG_SOURCE`. Preferences never contain trust records.

Set `AGENTSTART_CLAUDE_TRUST=0` to keep normal trust behavior while loading the
preferences. `AGENTLAUNCH_SHIM_BYPASS=1` skips the whole managed launch path.
Help/version, administrative commands, remote/cloud calls, safe/bare/restricted
modes, explicit `--setting-sources`, and unknown CLI options pass through
unchanged. Keep the argument classifier current when adding native options.
Use separate tokens for short options with values (`-r SESSION`, not `-rSESSION`).

Installation is the existing `scripts/install.sh --install` contract. It
converges both harness shims after the fleet installers. Funk's `funk stow`
installs the preferences link, keeping `.claude` a real directory.

## Verification

`tests/claude-invocation.py` covers local state preservation, idempotence,
concurrent launches, lock contention, malformed inputs, worktrees, alternate
homes, argument precedence, stdio, exit status, and exec identity. It runs in
`tests/validate.sh` without accounts or network services.

Run `python3 tests/claude-invocation-runtime.py` for the opt-in native PTY proof
(`CLAUDE_NATIVE_BIN` can select the stock executable). Native proof on Claude
2.1.263 used an isolated `CLAUDE_CONFIG_DIR`, fake API
key, and an unreachable loopback provider. In a real Terminal Control PTY,
the direct launch displayed the workspace trust dialog; the helper launch
reached the normal input prompt with the authored Sonnet model and selected
manual permission mode unchanged. A project SessionStart hook stayed disabled
before trust and ran after it; physical cwd, worktree, and main-root trust
entries and the unchanged preferences symlink were checked. The native plugin
writer was also checked against a settings
symlink: it updated the target and preserved the link, but keeping authored
preferences separate avoids its generated state entering Funk.

The [preference watcher](../harness-preferences.md) publishes validated snapshots,
reports native edits to authored fields, and retains a last-good copy during
invalid edits. It never rewrites Funk preferences or native settings.
