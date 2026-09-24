# 0042: Prune removed-MCP skills and their workflows from the default role

Accepted September 23, 2026. Supersedes the retained-skill and CLI-recording
portions of [ADR 0040](0040-collapse-explicit-roles-to-default.md), the
default-role `routing-receipt` use in
[ADR 0008](0008-native-history-routing-receipts.md), and the default-role HUD
recording mandate in
[ADR 0013](0013-managers-own-hud-recording.md). AgentHUD remains the fleet's
durable Work owner; [ADR 0010](0010-cut-over-active-work-to-agenthud.md)'s
work-owner cutover is unchanged outside this role's prompt.

The default role's `mcp.json` already omits the AgentAttention, AgentChats,
AgentGrok, AgentHUD, AgentKeys, AgentMux, AgentSounds, and AgentSurface MCPs.
The human asked that those owners' agent-facing surface be stripped from the
role rather than merely left unstarted. `roles/default/skills-exclude.json`
removes the corresponding dedicated skills — `attention`, `bus`, `chats`,
`grokbot`, `hud`, `keys`, and `sounds` — from the role's rendered skill
directory; AgentMux ships no standalone skill. `scripts/render-roles` links each
retained skill individually and records the filtered set in the ownership
receipt, so the existing attestation and independent-change refusal are
unchanged.

The authored prompt deletes the advice that presupposed those owners: the
AgentHUD Work/Assignment/Result lifecycle, its CLI recording duty, the
AgentChats `routing-receipt` call and decision-ID ledger, and the AgentAttention
grant path. It is replaced by nothing synthetic — there is no replacement
persistence mechanism, receipt format, or record schema in the role. Generic
native accountability remains: workers own bounded assignments and report to
their parent, the lead reviews returned evidence before accepting, outcomes
needing the human stay pending with the required response named, and model,
effort, and context are still chosen deliberately for each delegation.

This is a default-role boundary only. The common managed MCP inventory, the
shared skill set, each tool's installer, services, and other consumers are
unchanged. On September 23, 2026, the human also requested removal of indirect
routes to excluded skills from retained default-role guidance. The AgentStart
operator extension and the owning Brain, Browser, Desktop, Search, Wiki, and
Tend skills no longer prescribe those routes. Browser human handoff uses
AgentBrowse's supported `view` and an explicit human outcome instead of the
removed skill. The common inventory and independent tool workflows remain
available; this does not revoke tools already loaded by a session. Existing
loaded sessions and workspace snapshots keep earlier bytes until a normal
activation boundary.

Evidence: `roles/default/skills-exclude.json`,
`roles/default/APPEND_SYSTEM_PROMPT.md`, `roles/README.md`,
`scripts/render-roles`, `tests/render-roles.py`, `skills/fleet/MAP.md`,
`prompts/agentguidance/GUIDELINES.md`, and the owning skill templates.
