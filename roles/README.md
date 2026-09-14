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

## Conversational front and selective managers

The manager role keeps intent, authority, short status, steering and checked
delivery with the conversational lead. Brief coupled work stays direct;
substantial interacting judgments can go to a capable manager with bounded
outcome ownership. The lead checks decisive evidence rather than treating a
strong model's completion as approval or repeating its whole audit. This is
an existing-role responsibility pattern, not a new router role or mandatory
delegation layer. Worker responsibilities and inventories remain independent.

The accepted provisional model choice is Sol/low for the AgentVoice work
front, with selective stronger managers. Models remain configuration choices,
not prompt constants or a universal ranking. Existing snapshots and loaded
generations do not update when these sources converge. A future explicit
launch can select `--model gpt-5.6-sol --effort low`; inspect raw overrides and
saved-role ownership first, as described in AgentVoice's launch contract.
Frontend reattachment alone does not apply pending prompts or settings.

See [selective manager decision](../docs/adr/0009-conversational-front-selective-managers.md).

## Routing evidence

Both working roles use AgentChats `routing-receipt` when available to retain
short decision and acceptance records through existing native tool results.
AgentChats validates the schema but stores no new log. Its `routing` command
joins those receipts with exact Codex rollout calls, ancestry and native turn
configuration; missing receipts, native settings and acceptance remain unknown.
The tool's guide owns its detailed schema. Direct work, fresh delegation,
follow-up assignments and escalation all qualify when substantive; small
conversational exchanges do not need another tool call.

Land the AgentChats commands before publishing this guidance. Use the existing
resource sync for future role loads; do not restart calls or migrate snapshots.
This records concise reasons, not hidden reasoning, raw source bodies or a
training archive. The parent owns acceptance of a delegated result. Native
transcript retention remains the only automatic retention path.

See [routing receipt decision](../docs/adr/0008-native-history-routing-receipts.md).
