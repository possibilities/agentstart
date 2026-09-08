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

- `one_of` with `required: true` → `oneOf`, one branch requiring each selector
- `one_of` without → at most one; describe it
- `at_least_one` → `anyOf`, one branch requiring each selector
- `requires` → `dependentRequired`
- `conflicts` → describe it; `not`/`allOf` is legal but unreadable in practice

Each union branch includes the complete generated input object: its properties,
types, descriptions, defaults, baseline required fields, and unknown-property
policy. Add the branch's selector to that required set. Some MCP hosts,
including Executor's TypeScript preview, read union branches independently;
bare `required` fragments lose the root properties and required arguments.
Generate branches from the input schema rather than authoring those fields
again. Use input-mode conversion so a default does not become a required input.

A boolean selector represents a CLI flag being true: its branch requires the
property with `const: true`. Passing false must not select that branch. Keep
default values descriptive when materializing them would change explicit-flag
conflicts; apply those defaults in the shared handler.

More complex relations conditioned on another argument's value, such as an
anchor required only for `--to after`, go in the description in full.

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

Return the CLI's own JSON object in `structuredContent` and as a standalone
JSON text content block. This preserves the same envelope for native MCP
clients and aggregators that forward content but omit structured error data.
Keep plain-text results (Markdown, for example) as text; do not invent an
envelope around them. Keep diagnostic notes separate from the JSON payload.

`ok: false` becomes a tool error with `isError: true`. Its first text block
leads with `error.code`, then the message, then `recovery` when the contract
gives one. The envelope goes in `structuredContent` and a separate JSON text
block, so a caller can recover its fields without slicing JSON out of prose.
Preserve the tool's own error vocabulary and recovery. A classified failure
without a CLI envelope exposes those fields as a structured `error` object;
usage faults that have no domain code remain plain tool errors.

The `guide` agent tool must keep shared guidance and defaults accessible on
demand: aggregators do not necessarily forward server `instructions`. Native
workflow skills remain available through the harness's skill discovery.

## Stopping

A stdio server is built to outlive its caller, which is exactly why it must be
told to stop. It ends when the host closes stdio — the transport closing, or
`end`/`close` on stdin — and it must also end on SIGTERM, because that is what a
supervisor, a `timeout`, and a test harness all send.

**If the CLI installs its own SIGINT or SIGTERM handlers, the serve path must
honour them.** Installing a handler suppresses the runtime's own
terminate-on-signal, so a server that does not listen to whatever the handler
signals will survive SIGTERM and need SIGKILL. AgentScrape shipped exactly that
bug: its entrypoint aborts an `AbortController` on signal and every other
command receives it through `signal`, but serving was dispatched without one, so
SIGTERM aborted a controller nothing was listening to. Two servers stayed
resident for nine minutes and one was orphaned to init. A CLI that installs no
handler needs nothing here — the runtime terminates it normally.

Test it by spawning a real server, sending SIGTERM, and failing if the test has
to escalate to SIGKILL. `timeout` does not escalate on its own without
`--kill-after`, so an untested serve path leaks one process per run.

An idle server must also sit at ~0% CPU, blocked on a read. Steady CPU with flat
memory is a poll loop, not work.

## Declaring it

`mcp` is a command like any other and appears in the contract as
`audience: internal`, `mutates: true`, with `blocking: true` — it serves until
its transport closes. A server that is not in its own CLI's contract is exactly
the drift this project exists to prevent.

## Dependency

`@modelcontextprotocol/sdk` pinned at `1.30.0` — the fleet's existing pin, in
smolmux and agentutils. `McpServer` plus `StdioServerTransport`; follow smolmux's
`src/mcp.ts` and `src/mcp-server.ts` for house shape.
