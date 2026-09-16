# 0028: Expose AgentFX control to managers

Accepted September 16, 2026 as the manager control-plane completion of the
quota-aware routing loop.

## Decision

Add AgentFX's installed stdio MCP to the manager role with the private
`~/.config/agentfx/quota-routing.json` configuration. Keep it absent from the
worker role and from the shared global MCP inventory.

The MCP contributes exactly AgentFX's existing `targets`, `start`, `observe`,
and `control` operations. AgentFX retains durable execution/idempotency state,
Fx child ownership, and exact routing associations. AgentUsage retains account,
quota, credential, and provider-admission authority. AgentHUD retains semantic
Work, Assignment, Result, acceptance, and presentation state. Loading the MCP
does not make a configured target eligible and does not grant a worker further
delegation authority.

The role renderer expands `${HOME}` in both the command and configuration
argument before publication. The existing private config and state permissions
remain AgentFX's fail-closed boundary.

## Consequences

A newly loaded manager can use the supported manager-facing controller directly
instead of preparing one-shot request files. Workers cannot start sibling Fx
executions through their explicit role. Existing AgentVoice generations keep
their loaded MCP inventory until a later normal restart or replacement; role
sync and AgentRoles installation do not restart production AgentVoice.
