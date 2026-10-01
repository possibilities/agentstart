# 0051: Equip opted-in Devin ACP and Claude completions

Accepted October 1, 2026. Supersedes only the unconditional public ACP bypass
in [ADR 0047](0047-run-terminal-devin-in-place-with-cleanup.md), while preserving
normal pass-through, Stack's account-bound native ACP, and manual `/prime`.
Extends [ADR 0048](0048-share-devin-snapshots-across-concurrent-sessions.md) and
[ADR 0050](0050-serialize-devin-snapshot-registration-and-reaping.md)'s existing
snapshot/reference/lock owner to opted-in local ACP; no parallel renderer or
cleanup owner is created.

AgentStart installs AgentACP after AgentRoles. AgentACP's on-demand broker
launches Role-equipped private OpenCode ACP through AgentRoles and PATH
`devin acp` with the exact `AGENTSTART_DEVIN_ACP_ROLE=1` opt-in. The public
Devin wrapper starts native in the inherited process cwd but prepares the
default Role snapshot only for validated `session/new`/`session/load` cwds,
before forwarding their original protocol frames. `~/code` is a valid broker
startup directory, not a snapshot target. A bounded preparation worker keeps
unrelated protocol traffic responsive while the existing per-root lock waits.
Wrapper/native identities are saved by the existing AgentStart owner; the
periodic cleanup waits for every root reference to end. Protocol stdout remains
clean, failures retain the exact RPC ID, permissions remain native, and native
models, prompts, capabilities, session fields and notifications are not rewritten.

Admission readiness is witnessed by the original snapshot generation writer's
saved file manifest, not its early ownership marker or a later joiner's manifest.
Rendering failures and interrupted preparation can leave the marker and an
unfinished record behind; retries refuse that generation until the existing
process-identity cleanup can reconcile it. This strengthens ADR 0048's join
condition without a second readiness file, automatic recovery, or deletion of
foreign content. Checking completeness against the current Role would wrongly
require a shared snapshot to refresh during resource sync, so complete generations
retain the existing no-rewrite join behavior.

The default Role adds `agentacp mcp` to the common inventory and a native Claude
`monitors.json` completion Monitor. AgentRoles supplies a fresh
`AGENTROLES_INVOCATION_ID` and `AGENTROLES_HARNESS` to every Role-run process;
AgentACP's MCP and Monitor require Claude identity and reject controlled
OpenCode/Devin owners. This guard avoids recursive harness control without
inventing a second platform-specific inventory overlay. Non-Claude Role
consumers may expose an unavailable guarded server, not authorized control.

`scripts/render-roles` treats `monitors.json` as a separately hashed native
resource. Its additive v4 `monitors_sha256` ownership field allows safe,
idempotent publication and refuses independent destination changes. Existing
v2/v3/v4 receipts still migrate normally. The `content` object's
`agentvoice-role-content-v1` framing remains exactly prompt/MCP/skill content:
Monitor-only changes do not change voice generation hashes. Monitor shell
`${HOME}` expansion survives as native command syntax. This extends
[ADR 0017](0017-attest-role-content-and-audit-codex-copies.md), not its voice
framing, and preserves [ADR 0040](0040-collapse-explicit-roles-to-default.md)'s
single Role boundary.

No AgentACP resident LaunchAgent, external upstream patch, account selection,
automatic permission answer, forced `/prime`, or live app restart is added.
Devin receives Role resources, but manual guidance loading remains a documented
limitation. Fake-native public-shim transport/lifecycle tests and isolated Role
convergence tests cover the integration without credentials or live MCP effects.

Evidence: `scripts/{install-agent-clis,devin-invocation.ts,devin-acp.ts,devin-acp-prepare.ts,render-roles}`;
`roles/default/{mcp.json,monitors.json}`; `config/resources/mcp-servers.json`;
`tests/{devin-acp.test.ts,render-roles.py,install-agent-clis.test.ts}`.
