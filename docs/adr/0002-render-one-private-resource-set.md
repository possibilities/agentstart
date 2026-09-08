# 0002: Render one private resource set

AgentStart renders one fixed set under `~/.local/share/agentstart/resources`.
Claude receives a session-only `agent` plugin containing the shadcn MCP server,
and Codex receives a globally installed strictly skills-only `agent` plugin
whose qualified names are persistently disabled and session-enabled only by
AgentLaunch. AgentLaunch injects the same shadcn definition into Codex's
session config; neither harness receives it from ambient user configuration.

This keeps fleet skills out of Fx-visible ambient roots while preserving
Codex's native account, trust, and session stores. There is one installed
inventory rather than selectable packs or per-harness projections. Native
balancing, claims, guidance, unrelated user MCPs, and statuslines stay in
their owning systems.
