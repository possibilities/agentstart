# Devin invocations

AgentStart's public `~/.local/bin/devin` wraps the separately installed native CLI. Terminal sessions start **in the caller's current directory**; the wrapper discovers the Git root to place a temporary `.devin/` Role snapshot there. Existing tracked or untracked `.devin` content is never overwritten. The snapshot includes the current default Role skills, local MCP definitions, config-import restrictions, and a manual `/prime` skill. The native login, sessions, and arguments are unchanged. The temporary content is visible to Git until cleanup; the wrapper does not edit Git configuration or ignore files beyond its own snapshot `.gitignore`. Devin can work on uncommitted changes in the source checkout.

Many invocations may run in one Git root at once, and the root may already have a `.devin`. Each launch records its own `~/.local/state/agentstart/devin-invocations/<sha256-of-real-Git-root>-<invocation-id>.json` with the real cwd, an invocation ID, the shared snapshot ID, and its PID with microsecond-resolution kernel start time. The path is fixed even when a terminal overrides `XDG_STATE_HOME`, so the cleanup job sees it. Creation/registration and cleanup take the same per-root advisory lock; a launch cannot join a snapshot between cleanup's live-record check and deletion. The lock file persists in the private state directory so the inode cannot be replaced while in use. When `.devin` does not exist the invocation creates it and writes the whole snapshot. When `.devin` carries the canonical AgentStart ownership marker the invocation joins that snapshot generation — it claims matching files for the record but never rewrites them. When `.devin` exists without a marker the invocation merges: it writes the marker and any snapshot files that are absent, claims byte-identical files, and keeps conflicting project files with a stderr warning. A `.devin` that is not a directory, and a foreign or malformed ownership marker, still refuse. A resume from the same source directory joins or creates a snapshot; it does not require an old worktree.

The AgentStart-owned periodic `io.arthack.agentstart.clean-devin` LaunchAgent runs at login and every 30 seconds. It groups records by Git root and skips a root while any of its wrapper or native child identities remain alive, so a recycled PID cannot hold or prematurely clean a session and concurrent sessions never race the cleanup. Once every record for a root has ended, it verifies the exact ownership marker and removes only unchanged claimed files across the union of the group's manifests; new or edited files are left in place. A wrapper that died while creating a snapshot — marked, recorded, but missing its manifest — still has its whole staging directory removed when it made that directory itself; merges limit the partial-manifest removal to the marker. Unknown, malformed, and foreign state is not cleaned by guessing. The daemon never modifies a Git branch or a native Devin session.

`devin acp` normally passes through without a snapshot. Native utilities,
help/version, cloud commands and explicit `AGENTSTART_SHIM_BYPASS=1` keep that
bypass even when the opt-in below is present. Stack's account-bound direct native
ACP workers remain outside this wrapper. `/prime` is invoked manually, never
injected. The installer does not change the sticky `default` plugin; the
separate retirement helper still requires a disposable-profile native proof of
the installed wrapper before use.

Existing AgentStart-owned Devin worktrees from the former wrapper are preserved. A resume (`-c`/`-r`) inside one of those exact marked worktrees passes through to native Devin without creating a new snapshot; new sessions in ordinary project checkouts never create worktrees.

## Opted-in local ACP

AgentACP launches PATH `devin acp` with `AGENTSTART_DEVIN_ACP_ROLE=1`. Only the
exact value `1` enables the local newline JSON-RPC proxy (`0` or an absent value
keeps native pass-through; other values on local ACP refuse). It starts native
Devin in the unchanged process cwd, which may be the non-Git fleet directory
`~/code`. It creates no snapshot at startup. Before forwarding `session/new`
or `session/load`, it requires an absolute existing directory in a Git
repository and invokes the existing snapshot owner at that directory's real Git
root. The native session receives the original frame and exact requested cwd,
including a project subdirectory; no model, prompt, MCP parameters or native
session fields are rewritten.

One record per real root binds the ACP wrapper and its already-owned native
child identity through the existing `saveInvocation` path before admission.
Repeated sessions at one root share that reference; distinct roots get distinct
references. A second terminal/ACP invocation joins the existing generation.
References last for the ACP process, not an inferred session completion. The
periodic cleanup skips the root while **either** recorded process is alive;
it removes resources only when **both**, and all concurrent root references,
have ended. Marker changes refuse later admissions. Foreign
files are preserved with stderr-only conflicts under the existing merge rules.

The preparation worker serializes snapshot operations without blocking
unrelated requests, responses, notifications, extensions or permission answers
in the protocol loop. Forwarded input and native output retain their original
newline-frame bytes. Local parse errors use JSON-RPC `-32700`/null ID, invalid
session requests `-32600`/null ID, invalid cwd `-32602`/the exact request ID, and
snapshot/capacity failures `-32000`/the exact request ID. Rejected requests never
reach native. Error detail and conflicts go only to stderr. The proxy does not
answer native permission requests or auto-grant tool access.

Bounds are 8 MiB per newline-terminated frame, 32 queued admissions / 16 MiB of
pending frame bytes, and 256 distinct snapshot roots per ACP process. Capacity
errors reject only the excess admission. Oversized/truncated transport frames
close the process with a nonzero status. Input EOF and SIGINT/SIGTERM/SIGHUP
stop and reap only the owned native child, forwarding the actual signal (EOF
uses SIGTERM) with a two-second SIGKILL fallback. The existing cleanup service
handles ended resources; no second reaper or resident broker service is added.

Role skills and MCPs are available before native session admission, subject to
the existing project-conflict and shared-generation rules. Guidance remains the
manual `/prime` skill: ACP does not automatically load AgentStart's append
prompt and this integration makes no native-prompt-equivalence claim. See
[ADR 0051](adr/0051-equip-opted-in-devin-acp-and-claude-completions.md).
