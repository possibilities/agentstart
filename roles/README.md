# Manager and worker roles

AgentStart owns the human-facing `manager` role (formerly AgentVoice's
`default`) and assignment-focused `worker`. Each source directory contains
its prompt Markdown and its own `mcp.json`. Both initially carry the full
19-server fleet roster. Edit each role's inventory independently when their
needs diverge; changing the general fleet inventory does not silently change
either role's roster.

The normal `scripts/sync-skills` path renders launchable directories at
`~/.local/share/agentstart/resources/roles/manager` and `worker`. The renderer
expands `${HOME}` in MCP commands, links the shared skills directory, and links
prompts to their authored files here. Use the rendered role for launches:
source MCP commands are templates.

```sh
agentvoice server --role ~/.local/share/agentstart/resources/roles/manager
agentvoice server --role ~/.local/share/agentstart/resources/roles/worker
agentroles show ~/.local/share/agentstart/resources/roles/worker
```

AgentRoles can deliver these directories to Claude and Codex too. Codex CLI
skills require its explicit `agentroles install <role-path>` workflow; this
render does not register a global role name or automatically assign workers
to native children. AgentVoice registers role skills on its owned child.

Keep the two responsibility variants' shared working standards aligned.
Each has its own speech suffix, so either source directory can be moved
without a sibling prompt dependency. Keep native mode text within 1,600
UTF-8 bytes. AgentVoice alone consumes the `VOICE_*` files; other harnesses
retain their own native delegation restrictions. Only the actual AgentVoice
call root receives the controller's mailbox capability.

Existing workspace role snapshots and running calls retain their contents.
The old `resources/agentvoice/default` role is retired and no longer selected
or rendered. Its previous installed files are left untouched; this render does
not delete independently used roles or restart sessions.

See [role ownership decision](../docs/adr/0006-own-manager-worker-roles.md).
