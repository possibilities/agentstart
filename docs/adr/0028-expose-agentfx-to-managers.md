# 0028: Expose AgentFX control to managers

Accepted September 16, 2026 as the manager control-plane completion of the
quota-aware routing loop.

## Decision

Add AgentFX's installed stdio MCP to the manager role with the private
`~/.config/agentfx/quota-routing.json` configuration. Keep it absent from the
worker role and from the shared global MCP inventory.

The MCP contributes exactly AgentFX's existing `targets`, `start`, `resume`,
`observe`, and `control` operations. `resume` uses stock Fx session loading only
after a known terminal outcome and creates a fresh Execution, routing admission
and Assignment association; unknown outcomes remain non-resumable. AgentFX retains durable execution/idempotency state,
Fx child ownership, and exact routing associations. AgentUsage retains account,
quota, credential, and provider-admission authority. AgentHUD retains semantic
Work, Assignment, Result, acceptance, and presentation state. Loading the MCP
does not make a configured target eligible and does not grant a worker further
delegation authority.

Ordinary fixed-target starts and resumes use
`routing_source_revision: "broker_prepare"`. AgentUsage resolves the current
exact revision inside the locked catalog-validation and broker-preparation
transaction, and AgentFX records that resolved revision before launching Fx.
An exact aggregate revision is reserved for a caller intentionally fencing
admission to that exact snapshot. When fresh routing context exposes a compatible
eligible included-quota Grok target but the manager selects native Codex, the
routing receipt records a concise task-specific rationale. This adds evidence to
the existing per-assignment judgment; it does not make Grok routing automatic.

An explicitly human-enabled named automatic comparison profile is the narrow
exception. A profile may configure bounded source and counterpart harness,
provider, model, effort, and repetition values, but the manager infers no
unspecified variants and does not implement a general benchmark system. While
enabled, the profile gives every eligible Sol-, Terra-, or Luna-level root
assignment one isolated Grok AgentFX counterpart until the human disables or
changes it, when the work is repeatable and safe. The two candidates begin from
the same frozen packet and repository base, while the counterpart keeps a
separate tracked Work/Assignment lineage and output isolated for review; their
routing receipts identify the profile and pair. Astra-level judgment,
irreversible or otherwise non-repeatable external actions, and shared-device or
headful-resource work are ineligible. No comparison artifact is integrated
automatically. The named profile is opt-in durable manager-role state: automatic
inside its explicit scope, not a universal routing default.

The role renderer expands `${HOME}` in both the command and configuration
argument before publication. The existing private config and state permissions
remain AgentFX's fail-closed boundary.

## Revised comparison policy

The initial profile identifier and loose counterpart definition above were
superseded on September 18, 2026 by
[ADR 0030](0030-select-stage-one-comparison-profile.md). ADR 0030 retains the
human-enabled automatic and persistent behavior while narrowing it to the
digest-bound, one-shot Stage 1 `agentfx-stage-1-shadow` profile. It adds no
scheduler, continuation, fallback, or integration authority.

## Consequences

A newly loaded manager can use the supported manager-facing controller directly
instead of preparing one-shot request files. Workers cannot start sibling Fx
executions through their explicit role. Existing AgentVoice generations keep
their loaded MCP inventory until a later normal restart or replacement; role
sync and AgentRoles installation do not restart production AgentVoice.

Revised September 18, 2026 to include the resumable-session operation and its
fresh-admission boundary, broker-prepared default routing revision, and explicit
evidence when an eligible compatible Grok route is declined. The same revision
added the separately tracked, human-enabled automatic comparison profile; ADR
0030 later replaced its identifier and run contract without disabling it.
