# Operator AgentVoice configuration

`server.json` is the authored source for the existing
`~/.config/agentvoice/server.json` link. Keep this source under version control;
`agentvoice-config` owns link publication and preserves independent files.

The default role uses a conversation-first native delegation mode approved on
September 8, 2026. `features.multi_agent_v2.multi_agent_mode_hint_text` is sent
through AgentVoice's `orchestrator.config` passthrough. It lets the root delegate
substantial work, including a single blocking assignment, while staying with
the human; workers execute their assignments. This explicitly overrides native
delegation and model-selection defaults while preserving the user's choices,
full-history fork constraints, permissions and approvals. The stock Codex
binary, base prompt, Astra model and low effort are unchanged.

The policy text matches AgentVoice's `docs/delegation-policy.example.json`.
Its `docs/delegation-policy-audit.md`, ADR 0030 and
`scripts/delegation-policy-probe.ts` record the source audit and isolated
start/replacement/resume verification on stock 0.153.4. Update both policy
copies together and rerun that probe when changing the text or native version;
custom mode text is limited to 400 estimated tokens upstream.

This setting applies to calls using this server configuration, even if its role
is overridden. Use a separate server config for a different delegation policy.
Changes load on the next call or explicit runtime replacement. Updating this
file does not authorize restarting an active call.
