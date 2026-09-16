# 0015: Close scoped Work with explicit delivery

Accepted September 14, 2026. Refines [manager-owned recording](0013-managers-own-hud-recording.md).

The human requires managers to drive closure and communicate delivery, but rejects
a universal requirement for human acknowledgment of every completed implementation.
The actual Work scope decides whether landing, installation, production use or
human validation is required. Achieved implementation Work can close; the manager
tells the human what was delivered and is closing rather than silently dropping it.

Technical acceptance, presentation and a genuine human dependency remain distinct.
A tracked answer not acknowledged as heard stays visible, and required approval,
validation or a decision remains unresolved with the exact next human action.
A clear natural response suffices; no special approval word is required. Silence
and mere presentation do not settle an actual dependency. Follow-up is contextual,
respects conversation hold and unrelated topics, and creates no scheduler or
unrequested recurring reminder. Deferred delivery remains pending presentation.

AgentHUD already supports accepted results, presentation histories, Work waiting
state, next action and Attention references. This is a manager procedure using
those facts, not a schema migration or an acknowledgment field. Workers retain
their existing result-return responsibility. No role inventory or live session
state changes. Resource sync prepares future loads; loaded prompts and MCP guide
objects may remain older until the corresponding authorized future reload.

Evidence: manager APPEND prompt, shared GUIDELINES, roles README and AgentHUD's
owned skill/CLI guide/protocol. Validation uses role/resource rendering, native
mode length checks and installed-output inspection, without service restarts.

## September 14 clarification: reconcile every accepted outcome

An accepted historical no-dispatch resolution remained awaiting presentation after
the replacement guidance shipped. Delivery, closure and recovery must reconcile
all accepted Results, including superseded and interrupted outcomes, against
actual human communication. Replacement delivery or internal acceptance alone
does not establish presentation of the earlier disposition. Record missing
presentation with its evidence when already communicated; otherwise explain the
obsolete resolution at a suitable conversational boundary before recording it.
Preserve unpresented findings, hold and real pending decisions. This clarifies
manager procedure without automatic presentation, an acknowledgment gate, changed
store semantics or worker recording.

## September 15 clarification: investigation follows the practical objective

Diagnosis usually informs an underlying practical objective; it does not by itself
close or hide Work when the findings identify remediation. Keep the accepted
diagnosis as evidence, then revise or reopen Work and track the required delivery,
validation or concrete human decision. An investigation can instead end as
information when the human explicitly requested only that, decides no action is
warranted, or the evidence establishes that no change is needed. Remediation need
not be code. This is manager procedure over existing scope revisions, evidence and
next actions, without a fixed workflow or schema change.

## September 16 clarification: speculative tracking and human receipt

The human revised the earlier no-universal-acknowledgment choice for substantive
Results. When a voice question, request or follow-up plausibly represents
substantive work, managers create speculative Work before it can disappear from
the HUD. Temporary over-tracking is preferred to invisible lost work; an uncertain
item can later be merged, cancelled or closed as intent becomes clear. Scope,
disposition and next action stay aligned with current evidence. New and current
Work is active by default. Only an explicit human request moves it to waiting or
paused; dependencies, sequencing, external blockers, validation and needed human
responses leave it active with a truthful next action and, when supported, a
Needs you entry.

Every substantive delegation follows Work, Assignment, native dispatch, then
exact-turn binding. A failure or race that dispatches first is reconciled
immediately from native evidence rather than leaving an untracked worker. Routing
receipts, native dispatch and conversational promises remain evidence and never
substitute for Work or Result.

The manager records and reviews a Result before treating its outcome as complete.
After technical acceptance and presentation, the related Work remains actionable
until the human acknowledges the substantive Result or supplies the approval,
validation or decision its scope requires. A clear natural response is sufficient;
presentation and silence are not. Existing disposition, `nextAction`, evidence and
Attention references carry this procedure without a new acknowledgment field or
the separate Needs you UI/schema.
