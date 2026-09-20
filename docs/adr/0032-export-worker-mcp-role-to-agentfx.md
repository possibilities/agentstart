# 0032: Export the rendered worker MCP role to AgentFX

Superseded September 19, 2026 by
[ADR 0036](0036-retire-agentfx-role-and-installer-integration.md). The decision
below is retained as history; AgentStart no longer exports its worker roster to
AgentFX.

Accepted September 18, 2026.

## Decision

Keep `roles/worker/mcp.json` and its rendered
`~/.local/share/agentstart/resources/roles/worker/mcp.json` output as the single
authored worker MCP roster. AgentFX `code` executions may consume that rendered
output only after validating the private `agentstart-role-v4` ownership
receipt, its raw MCP SHA-256, and its framed `agentvoice-role-content-v1` MCP
digest. AgentStart continues to render the roster and receipt as owner-only
regular files and tests that the shipped worker roster has strict
`command`/`args` entries and contains neither AgentHUD nor AgentFX.

AgentFX owns its private mechanical stock-Fx configuration, executable lookup,
environment isolation, readiness semantics, lifecycle cleanup, and bounded
execution evidence. It does not own or persist another roster. AgentStart does
not render an Fx-specific copy. ACP-supplied MCP remains disabled, and the
AgentFX `read_only` profile receives no worker-role MCP until tool-level
read-only enforcement exists.

## Consequences

Native workers and later AgentFX `code` executions converge on one explicit
AgentStart policy source without an Fx fork patch. Normal role rendering and a
new AgentFX process are required before a source change affects a future
execution; active AgentVoice generations and existing Fx executions are not
reloaded. Discovering a tool confers no resource lease, messaging or email
authority, provider authority, or delegation beyond the parent-issued scope.
