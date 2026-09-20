# 0027: Require parent-issued delegation envelopes

Accepted September 16, 2026 under the explicit recursive fanout correction.
Extends [role ownership](0006-own-manager-worker-roles.md) and
[routing receipts](0008-native-history-routing-receipts.md).

## Decision

Manager and worker briefs explicitly grant a task-specific delegation envelope;
absence or ambiguity means zero child delegation. A nonzero grant names direct
and total descendant limits, allowed provider/model families, maximum effort,
purpose and re-delegation permission. Every delegated assignment consumes one
unit, including a new assignment on a reused child. Subtree allocations reserve
disjoint portions of the same total; children can pass only a smaller remainder
and cannot widen inherited restrictions. Completion does not replenish the
assignment budget. The issuing parent can explicitly revise its grant only
within its own inherited limits.

This replaces the earlier role-level two-concurrent-worker default and its
self-judged exceptions. The parent chooses the smallest correctly sized team
case by case. Explicit grants can permit additional suitable Terra or Luna
workers when independent work, total expected cost and review capacity justify
them. No universal headcount limit or price equivalence is introduced.

## Limits and delivery

These are behavioral instructions, not an authenticated admission ledger or
native pre-spawn gate. Routing receipts record the grant and allocation evidence;
they do not enforce it. The native harness remains responsible for actual worker
admission and execution state.

Render through AgentStart and check/install the explicit Codex role plugins.
Existing loaded runtimes retain their prompts until their supported authorized
reload boundary; publishing this content does not restart AgentVoice or prove
that existing descendants consumed it.

Revised September 19, 2026 by
[ADR 0036](0036-retire-agentfx-role-and-installer-integration.md) to remove the
retired provider-specific worker and admission language while preserving the
parent-issued envelope and native delegation rules.
