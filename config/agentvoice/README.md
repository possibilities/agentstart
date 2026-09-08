# Operator AgentVoice configuration

`server.json` is the authored source for the existing
`~/.config/agentvoice/server.json` link. Keep this source under version control;
`agentvoice-config` owns link publication and preserves independent files.

This file selects the managed default role, Astra/low, runtime logging and the
operator's permission opt-in. Delegation policy belongs to AgentVoice's default
role in `roles/default/VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md`. The managed role
renderer links that authored file alongside the append prompt; no policy text
is duplicated here. Selecting another role therefore does not inherit the
default role's conversation-first policy.

AgentVoice's ADR 0031 and `docs/delegation-policy-audit.md` describe the native
control, ownership conflicts and stock start/replacement/resume verification.
The role's mode file and a server config mode cannot both own the slot.
Changes load on the next call or explicit runtime replacement. Updating these
files does not authorize restarting an active call.
