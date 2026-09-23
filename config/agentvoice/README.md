# Operator AgentVoice configuration

`server.json` is the authored source for the existing
`~/.config/agentvoice/server.json` link. The ownership-checked
`agentvoice-config` installer publishes that link and preserves independent files.

The role selector names AgentStart's rendered `default` role at
`~/.local/share/agentstart/resources/roles/default`. Its prompts and MCP roster
are authored in [roles/default](../../roles/README.md). The retired `manager`
and `worker` outputs are removed by resource convergence when their ownership
receipts remain intact. The AgentVoice orchestrator defaults to Sol/high and passes the
currently advertised 872,000-token maximum context window as a native
thread-local Codex setting; an explicit launch override still wins. Model,
effort, context, debug and permission choices remain in this file.

The role's native mode file and a server-config mode cannot both own the slot.
Changes load on the next call or explicit runtime replacement. Existing workspace
role snapshots retain their captured settings. Updating source files or syncing
resources does not restart an active call.

The high-volume per-call debug log remains disabled by default.
