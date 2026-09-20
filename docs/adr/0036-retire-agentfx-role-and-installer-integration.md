# 0036: Retire AgentFX role and installer integration

Accepted September 19, 2026 as part of the active-fleet AgentFX/Grok execution
retirement.

## Decision

AgentStart no longer installs AgentFX through `install-agent-clis`, exposes its
MCP in the manager role, exports the rendered worker MCP roster to it, or
distributes AgentFX/Grok execution routing, resume, broker-preparation, automatic
comparison, or worker-roster policy. Manager and worker guidance retains the
provider-neutral native delegation and model-selection rules, parent-issued
delegation envelopes, AgentChats routing receipts, and AgentHUD manager
recording boundary.

AgentGrok and the GrokBot skill remain in the manager, worker, and common fleet
inventories because persistent bot collaboration is independent of the retired
execution-provider integration. The official Grok Build installation also
remains. AgentStart continues to install Fx through fxnk's exact Integration pin:
Fx and the maintained fork have independent consumers. Their installation
remains active after AgentLab's later retirement and does not depend on its
archived broker experiments.

The role renderer continues to attest each role's own MCP bytes and skills. It
no longer treats the worker role as an AgentFX input. Existing installed role
copies and active AgentVoice generations are not changed or restarted by this
source decision; normal source-only validation proves the next render, and a
separate authorized convergence can publish it later.

## History and boundaries

This supersedes [ADR 0028](0028-expose-agentfx-to-managers.md),
[ADR 0030](0030-select-stage-one-comparison-profile.md), and
[ADR 0032](0032-export-worker-mcp-role-to-agentfx.md). It revises only the
provider-specific part of
[ADR 0027](0027-parent-issued-delegation-envelopes.md). Those records remain in
place so prior manager behavior and rendered-role contracts remain explainable.

AgentStart does not move or delete the AgentFX checkout or runtime state, alter
credentials, install live resources, restart services, or patch the external Fx
fork in this decision.
