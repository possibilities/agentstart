# 0037: Supervise AgentLab's managed Codex launcher

Superseded by [0039](0039-retire-agentlab-runtime-integration.md).

Accepted September 20, 2026. Supersedes the bare Codex command in
[0034](0034-dedicated-agentlab-codex-app-server.md). A utility app-server launch
inherited native default authentication, which could be revoked even while the
AgentUsage managed pool was usable.

Keep the exact `io.arthack.agentlab.codex-app-server` label, ownership marker,
private Unix endpoint, desired-versus-installed socket semantics and launchd
supervision. Enter through the installed public command
`agentlab codex-daemon --listen unix:///absolute/socket`. AgentLab owns the
foreground launcher implementation and its child; AgentStart owns service
convergence and readiness. The separate console remains a client. AgentVoice
is outside this process, endpoint and lifecycle boundary.

AgentLab obtains private `agentusage prepare codex --json`, validates and applies
only its supported provider arguments/environment/unsets, and maintains the
opaque lease with authenticated HTTP renewal every 25 seconds and release on
exit. Ambiguous preparation or renewal fails closed. Its supported
`AGENTLAUNCH_SHIM_BYPASS=1` environment selects stock Codex through the existing
shim without AgentLaunch owning an app-server. No bearer or provider credential
enters a plist, argv or log. Logs now live under the manifest's owning tool,
`agentlab/codex-app-server.log`; the prior codex log is left intact.

Readiness remains launchd running plus the configured socket existing. It does
not connect, select accounts, submit turns or establish provider health.
AgentUsage must be installed and its existing daemon running before activation.
AgentLab and AgentStart source changes must be delivered together; AgentUsage
and AgentLaunch need no code or service changes.

Rollout prepares AgentLab's installed command first. Converging the daemon then
requires current restart authority; use only its exact service selector. Its
existing socket identity is preserved, so this fix does not require restarting
the console or AgentVoice. Fake-service tests verify the wrapper command,
credential-free environment, unchanged endpoint preservation and neighboring
service isolation. AgentLab's fake-provider tests verify auth/lease lifecycle.
