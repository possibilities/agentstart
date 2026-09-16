# Manager and worker roles

AgentStart owns the human-facing `manager` role (formerly AgentVoice's
`default`) and assignment-focused `worker`. Each source directory contains
its prompt Markdown and its own `mcp.json`. The manager exposes AgentHUD; the
worker omits its MCP and excludes the `hud` skill through `skills-exclude.json`.
Changing the general fleet inventory does not silently change either MCP roster.

The normal `scripts/sync-skills` path renders launchable directories at
`~/.local/share/agentstart/resources/roles/manager` and `worker`. The renderer
expands `${HOME}` in MCP commands and links prompts to their authored files.
The manager links shared skills; the worker gets a checked, filtered directory
of per-skill links. Sync converges added or removed shared skills while keeping
HUD excluded. Each ownership receipt records content-only hashes using the same
`agentvoice-role-content-v1` framing that AgentVoice reports for directory roles;
it covers resolved prompt, rendered MCP, and resolved skill bytes without storing
their bodies. Independently changed role contents are refused, not overwritten.
Use the rendered role for launches:
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
`scripts/sync-skills --check` runs AgentRoles' read-only
`install --check` comparison for both rendered roles when the resources and CLI
are available. It fails on stale copies but never refreshes them; run the
explicit install command for each role to accept and publish a change.

Keep the two responsibility variants' shared working standards aligned.
Each has its own speech suffix, so either source directory can be moved
without a sibling prompt dependency. Keep native mode text within 1,600
UTF-8 bytes. AgentVoice alone consumes the `VOICE_*` files; other harnesses
retain their own native delegation restrictions. Only the actual AgentVoice
call root receives `agentvoice.subagent_completion` payloads for its direct
native children; nested children continue returning to their immediate parent.

Existing workspace role snapshots and running calls retain their contents.
The old `resources/agentvoice/default` role is retired and no longer selected
or rendered. Its previous installed files are left untouched; this render does
not delete independently used roles or restart sessions.

See [role ownership decision](../docs/adr/0006-own-manager-worker-roles.md).
See [role freshness decision](../docs/adr/0017-attest-role-content-and-audit-codex-copies.md).

## Upstream fork patch and contribution gate

Both roles detect an external/upstream fork-patch decision before changing the
fork. Creating, maintaining, rebasing or applying a carried patch requires the
human's explicit approval after the agent presents the need, alternatives,
maintenance burden and a recommended non-patch route when available. Existing
workshop maintenance procedures govern execution only after that decision.

Before proposing or drafting an upstream issue or pull request, inspect current
contribution, security, template and reporting guidance and assess recent social
behavior for maintainer preferences, accepted patterns, review expectations and
communication norms. Opening or materially updating the concrete issue or pull
request requires explicit human approval. The manager owns that decision; a
worker returns its prepared candidate and evidence to the parent unless direct
human coordination was assigned. Ordinary authorized first-party implementation
continues under repository instructions without this extra gate.

See [upstream fork patch decision](../docs/adr/0025-require-human-approval-for-upstream-fork-patches.md).

## Conversational front and selective managers

The manager role keeps intent, authority, short status, steering and checked
delivery with the conversational lead. Brief coupled work stays direct;
substantial interacting judgments can go to a capable manager with bounded
outcome ownership. The lead checks decisive evidence rather than treating a
strong model's completion as approval or repeating its whole audit. This is
an existing-role responsibility pattern, not a new router role or mandatory
delegation layer. Worker responsibilities and inventories remain independent.

The manager's deployment guide treats **Sol/medium as a strong starting point
and midpoint, not a fixed default**. Actively choose smaller available models
for well-specified mechanical work, Sol for strong ordinary work, and higher
effort or capability when the expected benefit warrants it. Optimize accepted
results and whole-workflow subscription resources, including context, handoffs,
retries and review. Astra is appropriate when creativity, design,
design engineering, product engineering, deep thinking or architecture is central,
as well as for complex workflows. Valuable design/product judgment does not need
an exceptionally complex implementation to merit Astra. It identifies the current
AgentVoice root as Astra/low without asserting that every manager or native
child has those settings. Explicit human choices and actual native capabilities
win. The previously provisional Sol/low front was not activated by this change.

The concise catalog and briefing advice are in the manager APPEND only; the
worker prompt, inventories, native modes and runtime configuration are unchanged.
[Model-routing sources and limits](../docs/manager-model-routing.md) distinguish
the native model/effort catalog, AgentUsage's subscription observations and
public model/prompting guidance. Spark's separate finite quota is documented;
it is not enabled for this Codex-led role. Existing snapshots and loaded
generations do not update when these sources converge, and frontend reattachment
alone does not apply pending prompts or settings.

See [selective manager decision](../docs/adr/0009-conversational-front-selective-managers.md).
The operator-specific selection policy is recorded in
[manager model guide decision](../docs/adr/0016-manager-model-selection-guide.md).

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

## Conversation hold and spoken acknowledgments

The speech front owns spoken acknowledgments when present: “On hold” / “Off hold”
for conversational hold and “Muted” / “Unmuted” for conversational mute. The
working lead and workers propagate the preference internally without an echo.
Explicit conversational intent is distinct from physical audio commands/status
and push-to-talk. Mere typed work steering does not resume a held conversation.
Authorized work and internal returns continue while human presentation waits.

Direct-child completion delivery does not introduce a shared semantic hold state
or exactly-once speech mechanism. Source/render checks do not establish live
behavior.
See [hold guidance decision](../docs/adr/0012-conversation-hold-guidance.md).
See [direct completion decision](../docs/adr/0024-deliver-agentvoice-child-completions-directly.md).

## Manager-owned HUD records

Managers use HUD for substantive objectives, authority, assignments, dependencies,
reported results, acceptance, presentation and next decisions. Reconcile at start
or resume and meaningful work boundaries. Workers report to their parent through
the native harness; the manager records that report using its own actor and exact
worker/native/evidence attribution. Tiny replies need no record. Missing HUD
access leaves an explicit recovery note and pending reconciliation.

Managers default toward speculative durable tracking when voice intent plausibly
represents substantive work. Temporary over-tracking is preferable to invisible
lost work: an uncertain item can later be merged, cancelled or closed as intent
becomes clear. Managers keep scope, disposition and `nextAction` current, record
and review a Result before treating the outcome as complete, and keep the Work
actionable until the human acknowledges that substantive Result or supplies its
required approval, validation or decision. Routing receipts, native dispatch and
chat promises remain evidence; they never replace Work or Result.

New and current Work is `active` by default. Active and open Work is eligible to
advance, but does not select itself for dispatch. Only an explicit human request
moves it to `waiting` or `paused`; dependencies, sequencing, external blockers,
validation and needed human responses stay active with a truthful `nextAction`
and, when supported, a Needs you entry. When the session establishes a
pick-before-dispatch preference, the manager obtains confirmation of the specific
eligible Work before preparing or dispatching its worker.

Every worker dispatch has corresponding durable Work. The manager creates or
updates Work, prepares its Assignment, dispatches the native worker, then binds
the observed turn. A dispatch-first failure or race is reconciled immediately as
an exception from exact native evidence rather than left untracked.

The conversational manager retains intent, questions, HUD tracking, dispatch,
review, integration, acceptance, presentation and delivery. It delegates
substantive code implementation through the tracked Work and Assignment while
handling tiny answers, bounded inspection, HUD bookkeeping and genuinely cheaper
urgent corrections directly. At each useful execution boundary it alternates
advancing the next actionable active Work with inspecting every running and
returned Assignment. It records, reviews and lands a returned result before the
next substantive build dispatch, so completions do not accumulate unreconciled;
it uses the minimum correctly sized worker set.

AgentRoles marks its immediate AgentLaunch invocation as an explicit role resource
layer; AgentLaunch consumes that marker and does not add the global fleet overlay.
Default managed launches retain the global manager-oriented inventory. A role's
own MCP and skill paths remain the source for an explicit role launch.

This configures explicit role exposure, not native-child authorization. Native
children may inherit a manager's tools and prompts instead of loading the worker
role. Existing sessions and workspace snapshots keep their loaded resources;
source sync neither revokes inherited tools nor reloads a live generation. Workers
with older or inherited HUD tools must still return reports to their manager.

See [manager HUD ownership](../docs/adr/0013-managers-own-hud-recording.md).

## Resource lease records

The manager reconciles HUD resource and lease records at start/resume and every
grant, claim, holder/scope change and release. The record identifies the actual
holder and stable identity, exact scope and team coverage, sharing/capacity
rules, exact direct-user or explicitly affirmative Attention/AgentNotify grant evidence, current physical
state evidence, recheck and expiry. It represents evidence and coordination;
it never grants permission. Conflicting or uncertain records must be reconciled
before use. Missing agents, elapsed expiry and revocation do not prove a physical
release, so unresolved state stays reported under the manager's own actor.

Workers report resource facts, evidence and limitations to their parent and do
not write HUD. The existing human-granted lease rules for a real phone, desktop
and headful browser remain authoritative, as does explicit permission for
emulator/VM creation or start. Role rendering neither creates a grant nor
changes live resources.

See [resource lease decision](../docs/adr/0014-record-resource-leases-without-granting-permission.md).

## Scoped closure and human dependencies

After technical acceptance and delivery, the manager keeps the related Work active
and actionable until the human acknowledges the substantive Result. When the scope
requires approval, validation or a decision, the Work stays active with that exact
response in `nextAction` and, when supported, a Needs you entry. A clear natural
response is sufficient evidence;
presentation and silence are not. The manager then closes Work whose scoped goal
and human-response obligation are met and tells the human it is closing.

An investigation normally serves the human's underlying practical objective.
The manager preserves its diagnosis as evidence and, when remediation becomes
known, revises or reopens Work so the remaining delivery, validation or human
decision stays visible. Information-only requests, a human decision that no action
is warranted, and evidence that no change is needed can end as information; no
rule assumes remediation must be code.

Unacknowledged substantive Results and required approval, validation or decision
responses stay visible with a specific next human action. The manager follows up
at a useful conversational boundary, respecting hold and
unrelated topics, with no invented timed reminders. Deferred delivery remains
pending presentation rather than disappearing. Workers continue returning evidence
to the manager and do not take over human closure or HUD writes.

See [scoped closure decision](../docs/adr/0015-close-scoped-work-with-explicit-delivery.md).
