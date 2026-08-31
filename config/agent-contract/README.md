# The fleet agent contract

Every `agent*` CLI publishes one machine-readable self-description as
`<cli> guide --json`. `schema.json` beside this file is normative;
`scripts/validate-agent-contract.ts` enforces it, and
`tests/agent-contract.test.ts` proves the enforcement.

## Why one document

The description of a CLI used to be authored three or four times over. In
AgentBoard, the single refusal `existing_topic` was written independently in
`src/store.ts` (which raises it), `src/guide.ts` (which lists it), `src/help.ts`
(which explains it), and the `board` skill (which teaches it). Nothing compared
them, so nothing caught the day one of them went stale.

The contract inverts that. `guide --json` is authored; `--agent-help`,
`--agent-teaser`, and `--help` are **renders of it**. A CLI that still writes
its own agent help by hand has not adopted the contract, it has added a fifth
copy.

## The two layers

A contract carries both halves of what a caller needs, because the fleet
previously split them across mechanisms that did not line up — the repositories
with the richest conceptual description (`guide --json` in AgentBoard,
AgentWiki, AgentBrain) had no argument schemas, and the ones with real argument
schemas (`--help-json` in AgentScrape, `descriptor.ts` in AgentKeys and
AgentSearch) had no conceptual description.

**Conceptual** — `guidance` and `concepts`. What the tool is for, which verb to
reach for, what a caller habitually gets wrong, every `error.code` it can
return, and what its envelope and exit codes mean.

`guidance` stays prose on purpose. AgentSearch's depth routing — low by
default, medium up front for a multi-facet question, `fast` an opt-*down* for a
single fact rather than a cheap mode — is judgment. Flattened into enum
descriptions it stops being advice and becomes noise.

**Mechanical** — `commands[]`, each with typed `arguments[]`. Names, scalar
types, `choices`, `required`, `positional`, `repeatable`, defaults. Enough that
a consumer can build a typed call without parsing help text.

## Audience is the exposure decision

Both `meta.audience` and each command's `audience` are load-bearing, and they
are the contract's answer to *which subcommands form a proper programmatic
interface*:

- `meta.audience: agent` — the CLI is built for agents, and owes `guidance` and
  `concepts`. `operator` means humans and installers drive it; a webhook
  receiver has no routing doctrine and inventing one is worse than omitting it.
- command `audience: agent` — a verb an agent should call. This is the default
  surface a generated MCP server exposes.
- command `audience: operator` — real and supported, but human-driven: `doctor`,
  `backup`, `reindex`, `serve`, `gc`.
- command `audience: internal` — a protocol handler or subprocess entrypoint
  that is nonsense to call directly, such as AgentBrowse's `provider`.

The owner of the CLI answers this, not the consumer. That is the point: a
generated server asks the tool which of its verbs are for agents, instead of a
downstream list guessing and going stale.

**Every command appears**, including the ones no agent should call. Omission is
never how a command is hidden, because a missing command is indistinguishable
from an oversight.

## Rules a validator enforces beyond the shape

- `concepts.read_only_commands` must be exactly the commands declaring
  `mutates: false` — no omissions, no extras, no names that do not exist.
- An `operator` CLI may not contain an `agent` command.
- A positional carries no leading dashes; a flag carries them. The slip
  produces an argument nobody can pass, and it is the most common one.
- No field outside the contract. An `mcp_tool` hint belongs to the consumer,
  not here — the contract describes the CLI, and MCP is one reader of many.

## Adopting it

1. Emit `guide --json` inside the CLI's existing envelope, `contract_version: 1`.
2. Move the prose from `--agent-help` into `guidance` and `concepts`, then make
   `--agent-help` render from them. Deleting the second authorship is the step
   that pays; adding `guide` while keeping hand-written help buys nothing.
3. Declare `audience` and `mutates` on every command. These are judgments the
   CLI's owner makes once and everything downstream reads.
4. Add a conformance test in your own repository, and check yourself with
   `agentstart/scripts/validate-agent-contract.ts <cli>`.
