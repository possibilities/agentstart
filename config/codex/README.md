# Codex invocation profiles

Edit personal preferences in `~/code/funk/config/harnesses/codex.toml`. The next
normal `codex` launch reads that source; there is no apply or synchronization
step. AgentStart installs the wrapper through `scripts/install.sh --install`
and the existing `scripts/install-agentlaunch-shims` contract. Bun is required,
as it is for the fleet CLIs. Codex must support native profile files (0.134.0+;
runtime proof performed on 0.153.4).

The Codex shim first routes through AgentLaunch's normal account selection.
When the selected account's child reaches the shim with
`AGENTLAUNCH_LAUNCH=1`, `scripts/codex-invocation <native-codex> ...` launches
the native CLI with a unique `--profile agentstart-invocation-<uuid>`.
The profile lives directly under the existing `CODEX_HOME` (default `~/.codex`)
with mode 0600. The native binary, credentials, history, and account pin are
unchanged. Calls to an absolute native binary bypass the shim; launchers that
explicitly select a different native binary also bypass it.

Precedence, from lowest to highest, is Codex's base user config, Funk's
preferences, an explicitly selected native `--profile`, trusted project config,
then CLI overrides. The helper merges an explicit profile into the disposable
copy; arrays replace arrays. It never writes either source. Relative paths in
the authored TOML have native profile semantics: they resolve from `CODEX_HOME`,
not from Funk. Use appropriate absolute paths for file-valued settings; TOML
does not interpolate shell variables.

The invocation profile adds `trusted` for the physical effective working
directory (`--cd`/`-C` when supplied) and its enclosing project root. Git
directories and linked worktrees are supported; `project_root_markers` in the
base config, authored/selected profile, or a top-level CLI override controls
root discovery. An empty marker list trusts only the cwd. Trusting the root
is necessary for a launch inside a subdirectory to load the root's project
config. This intentionally removes the directory trust prompt for wrapped
launches. Separate native hook-trust checks and sandbox/approval policy still
apply. Trust elsewhere in the base config is preserved.

`projects`, `profile`, and legacy `profiles` are forbidden in the authored
file. Credentials, generated plugin/skill settings, and other machine state
stay in their existing homes. Claude, Pi, and Fx are outside this wrapper.

Interactive runs, `exec`/`e`, `review`, `resume`, and `fork` receive profiles.
Utility commands (including `app-server`, `mcp`, login, and plugin management),
help/version, remote-server connections, and explicit `--ignore-user-config`
pass through unchanged. `AGENTLAUNCH_SHIM_BYPASS=1` bypasses both balancing and
invocation profiles. An absent default authored file is optional and passes
through; a present malformed/unreadable file fails before Codex starts.
`AGENTSTART_CODEX_CONFIG_SOURCE` selects an alternative source and makes its
presence mandatory.

Native arguments and terminal streams are retained. The helper waits for its
child, propagates its exit status, forwards parent termination/hangup, and
deletes only its own profile after the child exits. Concurrent launches never
share profile files. SIGKILL or machine failure can leave an inert profile;
there is no background scavenger that could delete a live launch's profile.
Native preference writes during a session are not automatically saved back to
Funk. Edit Funk to make a preference durable.

For resume/fork, the wrapper uses the new invocation's cwd, or its explicit
`--cd`. AgentLaunch's `x-resume` already recovers the saved session's cwd. A
native picker that selects a different directory remains subject to Codex's
own directory selection/trust behavior; the wrapper doesn't read or rewrite
session databases.

`bun test tests/codex-invocation.test.ts` covers argument boundaries, trust,
profile precedence, source preservation, concurrent children, stdin, and
signal cleanup. `tests/validate.sh` includes it and verifies the installed
shim path.

For a stock-binary lifecycle check, run
`python3 tests/codex-invocation-runtime.py /absolute/path/to/native/codex`.
It serves a loopback Responses fixture in a disposable home, proves a model
turn and resume with fresh preferences and saved history, and makes no remote
model requests. The real TUI was also checked with the authored Funk source.
