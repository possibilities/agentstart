# The fleet agent contract

Every `agent*` CLI publishes one machine-readable self-description as
`<cli> guide --json`. `schema.json` beside this file is normative, and
`scripts/validate-agent-contract.ts` **executes** it through the small
interpreter in `scripts/json-schema-subset.ts` — it does not restate the rules.

That distinction is the whole point and it was learned the hard way: the first
version of this validator mirrored the schema by hand and drifted from it in
nine places, in both directions, while this file claimed the schema was
authoritative. Two authorships of one set of rules is the disease the contract
exists to cure, so the enforcement cures it too. Anything JSON Schema genuinely
cannot say lives in the validator's cross-field section, clearly separated.

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

## Nested commands

Commands form a tree, not a list. `agentwiki artifacts list`, `agentboard groom
export`, `agentbrowse profile create`, and `agentbrain jobs show` are real, and
flattening them loses information the fleet already publishes — AgentBoard's
guide names `groom export` in `read_only_commands` today.

A **group** holds a `name`, a `summary`, an `audience`, and `subcommands`. It is
not invocable, so it declares no `mutates` and no `arguments`. Its summary is
the line `--help` prints for the group, which is exactly what a flat list has
nowhere to put.

A **leaf** additionally declares `mutates` and `arguments`. Arguments scope to
the leaf that owns them, and that is what makes `required` mean something:
`--reason` is genuinely required on `artifacts rm` rather than nominally
optional on a collapsed `artifacts`.

Everything addressing a command by identity uses its **full path, space-joined**
— `read_only_commands`, and any consumer's naming. A consumer building tool
names joins the path with `_`: `artifacts list` becomes `artifacts_list`. That
join is specified here so fifteen repositories and one generator do not each
invent it.

## Arguments a type cannot describe

Three fields exist because real CLIs need them and a per-argument type cannot
carry them:

- **`constraints`** — relations between arguments. `one_of` (`agentbrain get`
  takes exactly one of `--document-id`, `--chunk-id`, `--source-uri`),
  `conflicts`, and `requires` (`agentsearch --depth high` requires
  `--allow-expensive`). Without this the selectors ship as three optional
  strings and a caller passes zero or two.
- **`stdin`** — a channel outside argv. `agentwiki add` reads the document body
  from standard input, and an out-of-process caller has no pipe. An
  `audience: agent` command may therefore not set `stdin.required`; accept the
  content inline as well. AgentAttention's `--context TEXT | --context-file
  FILE` is the pattern to copy.
- **`direction`** on a `format: path` argument — `out` marks a destination the
  command writes. `agentscrape fetch-markdown URL [DEST]` writes `DEST`, and a
  caller told only "path" will hand it an existing file and clobber it.

A **value grammar inside one argument** is not any of these. AgentSearch's
`--domains` is an allowlist, or a denylist with every entry `-`-prefixed, never
mixed. That belongs in the argument's `description`; the type system does not
carry it, and an author who assumes "typed arguments" covers it will drop it.

## Global arguments

`--json`, `--db`, `--format` and their kind are declared once in
`global_arguments`, not repeated in each command — for a 32-command CLI that is
the difference between a contract and a chore. A consumer building a call
surface should normally **suppress** them: they are transport and storage
concerns the caller has already fixed, not parameters a model should be asked
to choose.

## Adopting it

1. Emit `guide --json` inside the CLI's existing envelope, `contract_version: 1`.
2. Move the prose from `--agent-help` into `guidance` and `concepts`, then make
   `--agent-help` render from them. Deleting the second authorship is the step
   that pays; adding `guide` while keeping hand-written help buys nothing.
3. Declare `audience` on every command and `mutates` on every leaf. These are
   judgments the CLI's owner makes once and everything downstream reads.
4. Declare `constraints`, `stdin`, and path `direction` wherever they apply.
   These are the facts a caller cannot recover from a type, and the ones whose
   absence produces a call that looks well-formed and is not.
5. Add a conformance test in your own repository, and check yourself with
   `agentstart/scripts/validate-agent-contract.ts <cli>`.
