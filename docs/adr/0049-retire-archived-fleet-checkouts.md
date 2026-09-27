# 0049: Retire archived fleet checkouts from active installation

Accepted September 27, 2026. Supersedes the active HUD service and CLI
decision in [ADR 0011](0011-keep-agenthud-resident.md), and the common-inventory
retention in [ADR 0042](0042-prune-removed-mcp-skills-from-default-role.md).
Those decisions remain historical evidence rather than being rewritten.

The operator moved the named checkouts from `~/code` to `~/archive` and wants
them absent from AgentStart's active installer, MCP inventory and guidance.
Merely moving source makes editable command links dangle, leaves loaded
LaunchAgents running and retains copied skills in the fixed resource set.

AgentStart therefore drops the archived CLI participants, the HUD and Source
service templates, the Mux config and Source webhook installer paths, and the
obsolete AgentBrowse deployment config. Its LaunchAgent retirement path boots
out and removes only exact-marker-owned HUD and Source plists. The skill sync
prunes the retired dedicated names from the owned resource tree; the role still
excludes Chats independently. A bounded ownership-checked cleanup removes only
command links to the archived checkouts, the exact old Codex swap wrapper, and
the old Mux config link. Source,
Git history, private records, credentials and existing session snapshots are
not deleted or rewritten. New managed sessions receive the reduced inventory;
already running Codex sessions are not terminated.

This does not substitute implementations for consumers in other repositories.
AgentUsage and AgentStack's optional Grok Bot observation and Jobsearch's
AgentAttention workflow need their owners' separate decisions before their
dependencies can be considered healthy. Historical ADRs and prior receipts
retain their old names and paths as evidence, not active instructions.
