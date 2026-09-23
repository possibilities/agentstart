# 0014: Record resource leases without granting permission

Status: Superseded by
[0029](0029-retire-agenthud-resource-lease-recording.md).

Accepted September 14, 2026. Extends [manager-owned HUD recording](0013-managers-own-hud-recording.md).

Managers reconcile HUD resource and lease records at start/resume and at each
grant, claim, holder or scope change, and release. A record names the actual
holder kind and stable identity; exact scope and team coverage; exclusive or
shared use, capacity and rules; exact direct-user or explicitly affirmative
resolved Attention or AgentNotify grant evidence; and current physical-state evidence,
recheck time and expiry. Workers report these facts and limitations to their
parent; they do not write HUD.

The HUD record is coordination evidence, never permission. Conflicting or
uncertain authority or state must be reconciled before use. A missing agent,
elapsed expiry or revoked record does not prove the physical resource was
released; the manager verifies the resource where authorized and records any
unresolved state under its own actor. Notification delivery, read state,
silence, timeout and an unresolved Attention item establish no grant.

This adds an API-backed record to the existing resource-lease policy; it is not
an authorization engine. The human-granted lease requirements for real phones,
desktop control and headful browsers remain unchanged, as does the explicit
permission requirement for emulator or VM creation/start. This decision grants
no resource access, changes no live holder or service, and does not make native
session disappearance evidence of physical release.

Evidence: `roles/default/APPEND_SYSTEM_PROMPT.md`,
`prompts/agentguidance/GUIDELINES.md`,
`roles/README.md`, and `skills/fleet/MAP.md`.
