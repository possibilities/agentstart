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
HUD excluded. Independently changed role contents are refused, not overwritten. Use the rendered role for launches:
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

The speech front owns spoken hold/resume acknowledgments when present; the
working lead and workers propagate the preference internally without an echo.
Explicit conversational intent is distinct from physical audio commands/status
and push-to-talk. Mere typed work steering does not resume a held conversation.
Authorized work and internal returns continue while human presentation waits.

Mailbox entries and cached openings follow AgentVoice's server workspace session:
frontend detach and runtime replacement retain them; new_session and server
shutdown clear them. No shared semantic hold state or exactly-once speech
mechanism is introduced. Source/render checks do not establish live behavior.
See [hold guidance decision](../docs/adr/0012-conversation-hold-guidance.md).

## Manager-owned HUD records

Managers use HUD for substantive objectives, authority, assignments, dependencies,
reported results, acceptance, presentation and next decisions. Reconcile at start
or resume and meaningful work boundaries. Workers report to their parent through
the native harness; the manager records that report using its own actor and exact
worker/native/evidence attribution. Tiny replies need no record. Missing HUD
access leaves an explicit recovery note and pending reconciliation.

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

The manager closes implementation Work when its actual delivery objective is met
and tells the human what was delivered and is closing. Technical acceptance,
human presentation and an actual human dependency remain distinct. A universal
acknowledgment gate would create obligations the human did not request.

Tracked answers not acknowledged as heard stay visible; required approval,
validation or a decision stays unresolved with a specific next human action.
A clear natural response can settle it. Presentation and silence alone cannot.
The manager follows up at a useful conversational boundary, respecting hold and
unrelated topics, with no invented timed reminders. Deferred delivery remains
pending presentation rather than disappearing. Workers continue returning evidence
to the manager and do not take over human closure or HUD writes.

See [scoped closure decision](../docs/adr/0015-close-scoped-work-with-explicit-delivery.md).
