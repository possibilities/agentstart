# 0006: Own manager and worker roles in AgentStart

Accepted September 12, 2026. AgentStart takes ownership of AgentVoice's authored
default and worker prompts, renaming default to manager. A role must carry both
its working instructions and MCP roster, and the two rosters may diverge.

Each `roles/{manager,worker}` directory owns prompt Markdown and a complete
`mcp.json` template, initially identical to the current fleet inventory.
Separate inventories make role changes explicit without a roster selector
language or an implicit dependency on future additions to the common inventory.
Shared skills continue to come from the fixed resource set. The worker HUD
exclusion and filtered rendering in [0013](0013-managers-own-hud-recording.md)
supersede the original shared-directory behavior for that role.

The existing capability convergence calls `scripts/render-roles`, replacing
`render-agentvoice-role`. It needs no AgentVoice checkout: it renders each MCP
template for the account and links prompts from this repository, publishing
`resources/roles/{manager,worker}`. It checks existing ownership and MCP hashes
before replacement and validates both inputs before publishing either.

The tracked AgentVoice server config selects the manager directory. The existing
user config symlink therefore continues to work. Publish the new role directories
before changing that selector or removing AgentVoice's old prompt sources.
The old source paths and renderer are removed without aliases; previous installed
default-role residue is not deleted by unattended convergence.

AgentVoice remains a generic consumer and injects its own call control MCP.
This does not change native global configuration, assign native children a role,
migrate workspace snapshots, or restart a call. Source prompts retain their
existing native mode and speech-slot semantics. Existing active calls retain
their loaded prompt/MCP contents until a later call or authorized replacement.
