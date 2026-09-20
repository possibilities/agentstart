# 0030: Select the Stage 1 AgentFX comparison profile

Superseded September 19, 2026 by
[ADR 0036](0036-retire-agentfx-role-and-installer-integration.md). The decision
below is retained as history; the comparison profile is no longer active or
distributed by AgentStart.

Accepted September 18, 2026.

Historical status: enabled by explicit human direction on September 18, 2026,
then retired by ADR 0036 on September 19, 2026.

## Decision

Manager guidance automatically selects AgentFX Comparison profile
`agentfx-stage-1-shadow` revision 1 for every eligible repeatable root assignment
that would use native Codex Sol, Terra, or Luna. Before dispatch, the manager
freezes the native assignment's first-round task packet, inputs, instructions,
acceptance checks, and starting repository commit/base state. One native delivery
lane and one isolated AgentFX/Grok 4.6 medium shadow receive separate Works,
Assignments, routing receipts, worktrees, artifact roots, and binding-evidence
references. An immutable digest-bound manifest links the pair and records the
same frozen task packet and equivalent authority and tool bounds. The native lane
remains the delivery owner and may continue normally after the matched first
round; the shadow is comparison evidence only.

The shadow has one prompt, zero child delegation, and one admission attempt.
Managers do not steer, resume, chain, retry, automatically integrate, or silently
replace it, including after unknown acceptance or outcome. Astra assignments,
irreversible or otherwise nonrepeatable effects, shared or headful resources,
incompatible targets, and work that cannot be safely replayed are ineligible.
Stages 2 and 3 remain disabled. Ordinary native delivery obligations continue
under their existing Work, authority, review, and delivery contracts.

This supersedes the initial profile identifier and run details in
[ADR 0028](0028-expose-agentfx-to-managers.md), while preserving that decision's
human-enabled automatic behavior.

## Historical enabled-state source

While active, this accepted decision was AgentStart's durable source of truth for
the enabled state, and the authored manager prompt was its distributed execution
guidance. The profile remained enabled across assignments and newly loaded
manager sessions until ADR 0036 retired it. Per-assignment consent, silence, a
completed pair, a refused admission, or an unknown outcome did not change that
enabled state. Persistence required no scheduler or mutable runtime flag because
role rendering distributed the authored manager guidance.

## Ownership

AgentStart distributes manager selection and recording guidance. AgentFX owns
only its data contract and Fx Execution lifecycle. Native dispatch remains the
harness's operation, AgentUsage retains current eligibility and provider
admission, and AgentHUD retains Work, Assignment, Result, acceptance, and
presentation. This decision adds no scheduler, HUD action, model catalog,
fallback path, or execution authority.
