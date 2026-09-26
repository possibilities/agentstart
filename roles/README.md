# Default role

AgentStart owns one explicit working role, `default`. Its source directory
contains the human-facing manager prompt Markdown and its own `mcp.json`. The
role inventory omits AgentAttention, AgentChats, AgentGrok, AgentHUD, AgentKeys,
AgentMux, and AgentSounds MCPs. `skills-exclude.json` removes the
omitted owners' dedicated skills (`attention`, `chats`, `grokbot`, `hud`,
`keys`, `sounds`; AgentMux has no standalone skill) from the role's share of the
common skill set, and the prompt drops their owners' workflows rather than
prescribing a replacement system. Changing the general
fleet inventory does not silently change its MCP roster.

The normal `scripts/sync-skills` path renders launchable directories at
`~/.local/share/agentstart/resources/roles/default`. The renderer
expands `${HOME}` in MCP commands and links prompts to their authored files.
The role links each retained shared skill individually. Each ownership
receipt records content-only hashes using the same
`agentvoice-role-content-v1` framing that AgentVoice reports for directory roles;
it covers resolved prompt, rendered MCP, and resolved skill bytes without storing
their bodies. Independently changed role contents are refused, not overwritten.
Convergence removes the retired `manager` and `worker` rendered directories only
when their intact receipts still prove AgentStart ownership; independently changed
directories are preserved and stop the cutover.
Use the rendered role for launches:
source MCP commands are templates.

```sh
agentvoice server --role ~/.local/share/agentstart/resources/roles/default
agentroles show ~/.local/share/agentstart/resources/roles/default
agentroles ~/.local/share/agentstart/resources/roles/default -- fx
```

AgentRoles can deliver this directory to Claude, Codex, AgentVoice, Fx and
OpenCode. Codex CLI skills require its explicit `agentroles install <role-path>`
workflow; this render does not register a global role name or automatically
assign workers to native children. AgentVoice registers role skills on its owned
child. Fx and OpenCode need no install. Devin CLI has no per-invocation role
delivery; `agentroles install --devin <rendered-role>` installs a sticky
user-level plugin for every Devin session on this machine. Ordinary terminal
sessions instead use AgentStart's [temporary in-place snapshot](../docs/devin-invocation.md).
`scripts/sync-skills --check` runs AgentRoles' read-only
`install --check` comparison for the rendered role when the resources and CLI
are available. It fails on a stale copy but never refreshes it; run the
explicit install command to accept and publish a change.

Keep native mode text within 1,600 UTF-8 bytes. AgentVoice alone consumes the
`VOICE_*` files; other harnesses
retain their own native delegation restrictions. Only the actual AgentVoice
call root receives `agentvoice.subagent_completion` payloads for its direct
native children; nested children continue returning to their immediate parent.

Existing workspace role snapshots and running calls retain their contents.
The retired `manager` and `worker` source names are not aliases, and convergence
does not restart sessions or mutate independently owned role directories.

See [default-role cutover](../docs/adr/0040-collapse-explicit-roles-to-default.md).
See [role freshness decision](../docs/adr/0017-attest-role-content-and-audit-codex-copies.md).

## Role MCP boundary

The default role does not start the AgentAttention, AgentChats, AgentGrok, AgentHUD,
AgentKeys, AgentMux, AgentSounds, or AgentSurface MCP, and it does not ship those
owners' dedicated skills (`attention`, `bus`, `chats`, `grokbot`, `hud`, `keys`,
`sounds`; AgentMux has no standalone skill). This is an explicit-role
startup and skill boundary, not a retirement of those tools, their skills in the
common fleet set, the common managed inventory, or their independent services.
The role's prompt keeps generic worker report-and-review and notification
responsibilities without prescribing the omitted owners' commands.
Rendering a role change does not reload an active AgentVoice generation; it
becomes available at a later normal role load.

AgentStart no longer exposes or installs AgentFX, exports the worker roster to
it, or distributes provider-specific execution, resume, broker, or comparison
policy. Native delegation still follows the live collaboration tool catalog,
parent-issued delegation envelopes, and manager review. See
[the retirement decision](../docs/adr/0036-retire-agentfx-role-and-installer-integration.md).

## Upstream fork patch and contribution gate

The default role detects an external/upstream fork-patch decision before changing the
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

The default role's manager keeps intent, authority, short status, steering and checked
delivery with the conversational lead. Brief coupled work stays direct;
substantial interacting judgments can go to a capable manager with bounded
outcome ownership. The lead checks decisive evidence rather than treating a
strong model's completion as approval or repeating its whole audit. This is
an existing-role responsibility pattern, not a new router role or mandatory
delegation layer. Native workers remain bounded assignments, not another role.

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

The concise catalog and briefing advice are in the default APPEND.
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

The default working role chooses model, effort and context deliberately for each
substantive direct-work or delegation decision and explains routing to the human
only when it matters. It prescribes no synthetic receipt or second ledger: the
role neither starts an AgentChats MCP nor calls its `routing-receipt` command,
and native transcript retention remains the only automatic retention path.

Use the existing resource sync for future role loads; do not restart calls or
migrate snapshots.

See [routing receipt decision](../docs/adr/0008-native-history-routing-receipts.md)
and [the default-role skill prune](../docs/adr/0042-prune-removed-mcp-skills-from-default-role.md).

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

## Worker reports and review

Workers report to their parent through the native harness; the manager reviews
each returned report against its evidence before accepting, integrating or
requesting changes, and presents accepted results at the right conversational
boundary. Returned work must not accumulate unreconciled. Every worker dispatch
has a bounded assignment and a return path to its parent; when dispatch
acceptance is uncertain — a failure, a race, or a lost response — the manager
checks exact native state before retrying rather than leaving an untracked
worker or duplicating the dispatch. An outcome still needing the human's
approval, validation or decision stays pending with that response named;
silence is not a response.

The conversational manager retains intent, questions, dispatch, review,
integration, acceptance, presentation and delivery. It delegates substantive
code implementation through bounded assignments while handling tiny answers,
bounded inspection and genuinely cheaper urgent corrections directly. It uses
the minimum correctly sized worker set; at the root, that can use every
available root-owned child slot for genuinely useful, independent,
non-overlapping work while preserving integration and review capacity, with no
fixed two-worker or other arbitrary cap. Each root-level pick still needs the
human's confirmation when the session has a pick-before-dispatch preference; it
is not a permanent worker cap.

AgentRoles supplies an explicit role resource layer to its native harness
invocation. The bare permission shim adds no fleet overlay. The default role's
own MCP and skill paths remain the source for an explicit role launch.

This configures explicit role exposure, not native-child authorization. Native
children may inherit the manager's tools and prompts; there is no separate
worker role to select. Existing sessions and workspace snapshots keep their
loaded resources; source sync neither revokes inherited tools nor reloads a live
generation.

See [manager HUD ownership](../docs/adr/0013-managers-own-hud-recording.md),
[default-role cutover](../docs/adr/0040-collapse-explicit-roles-to-default.md),
and [default-role skill
prune](../docs/adr/0042-prune-removed-mcp-skills-from-default-role.md) — the
durable recording mandate those earlier decisions attached to this role is
removed; generic native report-and-review accountability remains.

## Human-controlled resources

Managers verify direct authority and physical state before using or handing off a
limited resource. A direct user instruction or an explicitly affirmative resolved
AgentNotify response can supply the exact grant; delivery, read state,
silence and timeout cannot. Workers return material holder, scope, grant, state and
release facts to their parent for direct coordination. Missing agents, elapsed
expiry and revocation do not prove physical release.

The existing human-granted lease rules for a real phone, desktop and
headful browser remain authoritative, as does explicit
permission for emulator/VM creation or start. Role rendering neither creates a
grant nor changes live resources.

See [the retirement decision](../docs/adr/0029-retire-agenthud-resource-lease-recording.md).

## Scoped closure and human dependencies

After technical acceptance and delivery, an outcome that still needs the human's
approval, validation or decision stays open with that exact response named as
the next step. A clear natural response is sufficient evidence; presentation and
silence are not. The manager tells the human when work whose scoped goal and
human-response obligation are met is closing.

An investigation normally serves the human's underlying practical objective.
The manager preserves its diagnosis as evidence and, when remediation becomes
known, keeps the remaining delivery, validation or human decision visible.
Information-only requests, a human decision that no action is warranted, and
evidence that no change is needed can end as information; no rule assumes
remediation must be code.

Unacknowledged substantive outcomes and required approval, validation or
decision responses stay visible with a specific next human action. The manager
follows up at a useful conversational boundary, respecting hold and unrelated
topics, with no invented timed reminders. Deferred delivery remains pending
presentation rather than disappearing. Workers continue returning evidence to
the manager and do not take over human closure.

See [scoped closure decision](../docs/adr/0015-close-scoped-work-with-explicit-delivery.md).
