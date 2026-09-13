# Operator AgentVoice configuration

`server.json` is the authored source for the existing
`~/.config/agentvoice/server.json` link. The ownership-checked
`agentvoice-config` installer publishes that link and preserves independent files.

The role selector names AgentStart's rendered `manager` role at
`~/.local/share/agentstart/resources/roles/manager`. Its prompts and MCP roster
are authored in [roles/manager](../../roles/README.md); the worker role has its
own inventory. Model, effort, debug and permission choices remain in this file.

The role's native mode file and a server-config mode cannot both own the slot.
Changes load on the next call or explicit runtime replacement. Existing workspace
role snapshots retain their captured settings. Updating source files or syncing
resources does not restart an active call.
