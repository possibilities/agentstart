# Generating an MCP surface from the contract

Every `agent*` CLI that exposes an MCP server does it as its own `<cli> mcp`
subcommand, serving stdio from inside the CLI process. There is no separate
bridge repository and no subprocess: the server reads the CLI's own contract and
dispatches through the CLI's own command table, in process.

This file is the mapping. It exists so seven repositories implement one mapping
rather than inventing seven — the same reason the contract itself exists.

## Which commands become tools

Exactly the **leaves** whose `audience` is `agent`. Not groups, which are not
invocable. Not `operator`, which is human-driven. Not `internal`, which is
nonsense to call — including `mcp` itself.

The CLI's owner already made this judgment when writing the contract. A server
that second-guesses it, by hiding an agent leaf or exposing an operator one,
has moved the decision back to the consumer and broken the point.

## Names

The command's **full path, joined with `_`**: `artifacts list` → `artifacts_list`,
`groom export` → `groom_export`. Do not prefix with the CLI name — the host
already namespaces by server.

## Input schema

From the leaf's `arguments[]`, plus `global_arguments` whose `role` is `call`.
Everything else is suppressed: `output-format`, `store-selection`, and `meta`
are concerns the caller has already fixed, and asking a model to choose `--db`
is asking it to guess.

| Contract | Schema |
| --- | --- |
| `type` | the JSON Schema type, verbatim |
| `description` | the property description |
| `required: true` | listed in `required` |
| `choices` | `enum` |
| `default` | `default` |
| `minimum` / `maximum` | the same keywords |
| `csv: true` | keep it a `string`; say in the description that values are comma-joined, and let `format` describe the element |
| `repeatable: true` without `csv` | an `array` of the scalar type |
| `repeatable` **and** `csv` | an `array`; join with commas when invoking |
| `format: "ref"` | stays a string — say in the description that a label or unambiguous phrase resolves, so a caller does not hunt for an id |
| `format: "path"`, `direction: "out"` | say plainly that the command WRITES this path, and that a relative path resolves against a working directory the caller did not choose |

Positional arguments are ordinary properties; the dispatcher knows their order
from the contract.

## Constraints

Express them in the schema where JSON Schema can, and in the description always
— a caller that cannot see the rule will break it, and a schema-only rule is
invisible in most host UIs.

- `one_of` with `required: true` → `oneOf` of single-property `required` shapes
- `one_of` without → at most one; describe it
- `at_least_one` → `anyOf` of single-property `required` shapes
- `requires` → `dependentRequired`
- `conflicts` → describe it; `not`/`allOf` is legal but unreadable in practice

A relation conditioned on another argument's **value** has no representation.
It goes in the description, in full.

## Annotations

Derived, not judged again:

| Annotation | From |
| --- | --- |
| `readOnlyHint` | `mutates === false` |
| `destructiveHint` | `mutates` and the verb removes or overwrites — `rm`, `destroy`, `gc`, an `out` path |
| `idempotentHint` | calling twice with the same arguments leaves the same state; a capture that refuses a duplicate is idempotent, one that appends is not |
| `openWorldHint` | the command reaches the network |

## Instructions

The server's `instructions` is the contract's `guidance`, followed by what
`concepts` says a caller must know: the envelope, the error codes with their
recovery, and `agent_defaults`. This is the half of the contract a tool schema
cannot carry, and dropping it ships a surface that works and is used wrongly.

Per-command `guidance` appends to that tool's description.

## Blocking and cost

A command with `blocking: true` says so in its description, in the first
sentence. A host with a request timeout has no other way to know.

A command that spends money or quota says that too, in the first sentence.
`mutates` cannot express it: `agentsearch ask` writes nothing and bills a card.

## Results

Return the CLI's own envelope. `ok: false` becomes a tool error whose message
leads with `error.code`, then the message, then `recovery` when the contract
gives one — the recovery line is the difference between a caller that retries
correctly and one that retries identically.

## Declaring it

`mcp` is a command like any other and appears in the contract as
`audience: internal`, `mutates: true`, with `blocking: true` — it serves until
its transport closes. A server that is not in its own CLI's contract is exactly
the drift this project exists to prevent.

## Dependency

`@modelcontextprotocol/sdk` pinned at `1.30.0` — the fleet's existing pin, in
fmx and agentutils. `McpServer` plus `StdioServerTransport`; follow fmx's
`src/mcp.ts` and `src/mcp-server.ts` for house shape.
