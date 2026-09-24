# 0040: Collapse explicit roles to default

Accepted September 23, 2026. Supersedes the two-role ownership and naming in
[ADR 0006](0006-own-manager-worker-roles.md), the explicit-role exposure portions
of [the AgentHUD cutover](0010-cut-over-active-work-to-agenthud.md) and
[manager-owned HUD recording](0013-managers-own-hud-recording.md), and the
two-copy freshness surface in
[ADR 0017](0017-attest-role-content-and-audit-codex-copies.md).
The retained HUD skill, CLI recording duty, and AgentChats `routing-receipt`
use described below are superseded September 23, 2026 by
[ADR 0042](0042-prune-removed-mcp-skills-from-default-role.md), which removes
rather than replaces those workflows; the single-role ownership and MCP
omissions remain current.

AgentStart owns one explicit working role named `default`. It carries the former
manager prompts and shared skills. The separate `worker` role is removed; native
children remain bounded workers under the default role's delegation and return
contracts, but no role directory or automatic role selection is associated with
that runtime responsibility.

The default role omits the direct MCP servers for AgentAttention, AgentChats,
AgentGrok, AgentHUD, AgentKeys, AgentMux, AgentSounds, and AgentSurface. These
omissions belong to its complete authored `mcp.json`; they are not inherited from
or expressed as a selector over the common inventory. This narrows explicit role
startup without retiring any fleet tool. The common managed inventory, checkout
installers, LaunchAgents, skills, commands, and cross-tool consumers remain
unchanged. The role's manager retains the HUD skill and durable Work recording
responsibility through the installed AgentHUD command. Routing receipts use the
installed AgentChats command rather than a role-provided AgentChats MCP.

Resource convergence renders `resources/roles/default` and removes the old
`manager` and `worker` outputs only when their receipts and contents still prove
AgentStart ownership. An independently changed old directory is preserved and
blocks the cutover instead of being deleted. There are no compatibility aliases.
The AgentVoice selector moves to `default`; AgentRoles publishes that same role
to Codex and Devin, while Claude, AgentVoice, Fx, and OpenCode consume it through
their normal per-launch contracts.

Existing loaded sessions and workspace-role snapshots retain earlier bytes until
an explicit normal activation boundary. Convergence does not restart an active
call, rewrite a snapshot, or revoke inherited native tools.

Evidence: `roles/default`, `scripts/render-roles`, `scripts/render-capabilities`,
`scripts/check-role-plugins`, `config/agentvoice/server.json`,
`tests/render-roles.py`, `tests/validate.sh`, and `skills/fleet/MAP.md`.
