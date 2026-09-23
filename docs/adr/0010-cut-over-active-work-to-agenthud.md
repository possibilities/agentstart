# 0010: Cut active work over to AgentHUD

Service-lifecycle portion superseded September 14, 2026 by
[ADR 0011](0011-keep-agenthud-resident.md). The work-owner cutover and Board
preservation decisions remain current. The original both-role exposure is
superseded by [ADR 0013](0013-managers-own-hud-recording.md): managers retain HUD
and workers report to them without direct HUD recording.
Explicit-role AgentHUD MCP exposure is further superseded by
[ADR 0040](0040-collapse-explicit-roles-to-default.md); the common managed
inventory still exposes AgentHUD.

Accepted September 13, 2026. The human chose AgentHUD as the single active
durable Work owner for managed sessions and explicitly rejected a Board
redirect or dual-write transition.

The shared MCP inventory and both AgentStart roles expose `agenthud mcp` and no
longer expose `agentboard mcp`. The fixed-resource sync ships AgentHUD's
tool-owned `hud` skill while excluding and pruning the exact legacy skill names
`board` and `groom`. Operator guidance and Wiki routing send new durable work to
HUD. Existing loaded sessions can retain their old MCP and skill snapshot until
they are reloaded.

AgentHUD now owns the `agenthud` source in the independent `~/code/agenthud`
checkout and publishes the normal fleet `scripts/install.sh --install`
contract. AgentStart invokes that owner directly. The HUD installer prepares
the command, dependencies, and web assets only; it does not restart or
configure AgentVoice or a service. No `agentvoice` command redirect exists.

AgentBoard remains installed and its existing data, operation history, command,
and stdio MCP implementation remain intact for archival queries and migration
work. No AgentStart cutover step mutates Board records. A bounded audit found no
AgentBoard socket service or endpoint in current source or runtime, so this
change neither creates nor claims one. New work is recorded only in AgentHUD.

Evidence: `config/resources/mcp-servers.json`, `roles/{manager,worker}/mcp.json`,
`scripts/install-agent-clis`, `scripts/sync-skills`,
`prompts/agentguidance/GUIDELINES.md`, and `skills/fleet/MAP.md`.
