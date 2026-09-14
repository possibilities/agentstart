# 0010: Cut active work over to AgentHUD

Accepted September 13, 2026. The human chose AgentHUD as the single active
durable Work owner for managed sessions and explicitly rejected a Board
redirect or dual-write transition.

The shared MCP inventory and both AgentStart roles expose `agenthud mcp` and no
longer expose `agentboard mcp`. The fixed-resource sync ships AgentVoice's
tool-owned `hud` skill while excluding and pruning the exact legacy skill names
`board` and `groom`. Operator guidance and Wiki routing send new durable work to
HUD. Existing loaded sessions can retain their old MCP and skill snapshot until
they are reloaded.

AgentVoice owns the `agenthud` source and a separate
`scripts/install-hud.sh --install` contract. AgentStart invokes that contract
after the existing AgentVoice installer. The HUD installer prepares the command
and web assets only; it does not restart or configure the AgentVoice service.
This preserves checkout ownership without creating a fictitious `agenthud`
repository or an `agentvoice` command redirect.

AgentBoard remains installed and its existing data, operation history, command,
and stdio MCP implementation remain intact for archival queries and migration
work. No AgentStart cutover step mutates Board records. A bounded audit found no
AgentBoard socket service or endpoint in current source or runtime, so this
change neither creates nor claims one. New work is recorded only in AgentHUD.

Evidence: `config/resources/mcp-servers.json`, `roles/{manager,worker}/mcp.json`,
`scripts/install-agent-clis`, `scripts/sync-skills`,
`prompts/agentguidance/GUIDELINES.md`, and `skills/fleet/MAP.md`.
