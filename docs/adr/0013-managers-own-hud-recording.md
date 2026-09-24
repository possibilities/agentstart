# 0013: Managers own HUD recording

Explicit-role AgentHUD MCP exposure is superseded September 23, 2026 by
[ADR 0040](0040-collapse-explicit-roles-to-default.md). The default role's
retained HUD skill and durable-recording mandate are further superseded
September 23, 2026 by
[ADR 0042](0042-prune-removed-mcp-skills-from-default-role.md); the native worker
reporting boundary remains current. There is no separate worker role.

Accepted September 14, 2026. Extends [role ownership](0006-own-manager-worker-roles.md)
and supersedes both-role HUD exposure in [0010](0010-cut-over-active-work-to-agenthud.md).

The human requires workers to report to managers, with managers rolling up durable
HUD records. Giving workers the same HUD tools and discovery skill encourages
competing bookkeeping and actor impersonation. The manager prompt explicitly owns
substantive Work reconciliation at start/resume and meaningful boundaries, including
assignments, reported results, acceptance, presentation and next decisions. Tiny
replies are exempt; unavailable HUD leaves a recovery note, not a claimed write.

The worker roster omits `agenthud`, and `skills-exclude.json` excludes `hud`.
The role renderer publishes a checked per-skill directory for exclusions and keeps
the manager's shared skill link. A versioned ownership receipt permits migration
of intact older generated roles, converges shared skill additions/removals and
refuses independently changed role or skill contents before publishing either role.

Explicit AgentRoles launches mark their immediate AgentLaunch resource layer;
AgentLaunch consumes that signal instead of re-adding the global fleet overlay.
Default launches retain their manager-oriented inventory. This closes accidental
role-overlay leakage without changing account selection or native launch policy.
AgentHUD's own guide and skill require the lead/issuer to record a worker report
using the manager's actor, retaining assignment, exact native and report evidence.
Existing store authorization already permits this; no schema or authentication
change is needed. Returned, accepted and presented remain separate facts.

This is a tool-exposure and recording contract, not a security boundary. Native
children can inherit tools rather than selecting a worker role; loaded generations
and workspace snapshots keep old resources until an explicit future load. No live
restart, snapshot migration, direct worker write, native dispatch or shared hold
mechanism is introduced. Board historical access remains preserved.

Validation covers filtered-role migration, convergence, tamper refusal, exact HUD
rosters and native-mode length; launcher tests cover explicit-role suppression and
unchanged default launches. Supported installation and resource sync prepare future
loads without proving everyday human behavior in existing sessions.
