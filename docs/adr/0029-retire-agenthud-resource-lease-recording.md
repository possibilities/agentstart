# 0029: Retire AgentHUD Resource and Lease recording

Accepted September 17, 2026. Supersedes
[0014](0014-record-resource-leases-without-granting-permission.md) and follows
AgentHUD's removal of its Resource and Lease domain.

## Context

AgentHUD now owns durable Work, Assignment and Result evidence only. Its Resource
and Lease records, mutation operations, projections and browser inventory were
removed because they duplicated authorization and physical-state coordination
owned by the tools and people controlling those resources. AgentStart guidance
still required managers to write the retired records and advertised fleet routes
that no longer exist.

The resource permission boundary remains necessary. A real phone, desktop,
headful browser, emulator or VM can require direct human authority and a durable
Attention or AgentNotify handoff. Authority and physical release remain distinct:
delivery, read state, silence, timeout, expiry, revocation or a missing agent do
not prove a grant or physical release.

## Decision

AgentStart no longer directs managers or workers to create, reconcile or project
AgentHUD Resource or Lease records. Managers do not create proxy Work solely to
replace that inventory. The HUD fleet route retains only its AgentChats dependency
for exact Codex transcript bindings.

Managers verify current authority and physical state directly before resource use
or onward handoff. A direct user instruction or an explicitly affirmative resolved
Attention or AgentNotify response can supply the exact scoped grant. Teams return
material holder, scope, coverage, state and release facts through their ordinary
parent or human handoff. Missing authority is requested through the notification
owner, and release is announced there. These facts can affect a Work dependency or
next action, but AgentHUD does not persist them as a separate resource ledger.

Earlier roles and sessions may retain the superseded guidance until their normal
resource or session reload. Source rendering and snapshot generation do not reload
a live agent, restart AgentVoice or AgentHUD, or change any physical resource.

## Consequences and validation

AgentHUD and AgentStart once again agree on the durable domain boundary. Physical
resource permission stays conservative without an unavailable bookkeeping API.
Role-rendering tests pin both the absence of HUD resource recording and the
continued direct human/Attention/AgentNotify authority rules. The fleet map and
generated field-guide snapshot remove the retired dependency and prose.
