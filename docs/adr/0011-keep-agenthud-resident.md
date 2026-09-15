# 0011: Keep the AgentHUD view resident under AgentStart

Accepted September 14, 2026. The human wants the HUD continuously available at
the same kind of editable, fixed local origin used by the AgentVoice web
interface.

AgentStart owns `io.arthack.agenthud.serve`, a resident user LaunchAgent that
invokes `~/.local/bin/agenthud serve`. The command owns the fixed Portless route
`https://agenthud.localhost` and defaults to AgentHUD's editable Vite/HMR
source. Its explicit production mode remains available to the command owner but
is not the managed default. The job uses the fleet's standard ownership marker,
private combined log, pinned `HOME` and `PATH`, login start, keep-alive policy,
standard process priority, and throttled failure retry.

The independent AgentHUD checkout owns the `agenthud` source and its ordinary
fleet installer. That installer prepares the editable command, dependencies,
and production assets without starting, stopping, or configuring a service.
This record supersedes only ADR 0010's expectation that no HUD service would be
installed. AgentVoice remains a separately observed runtime and still
exclusively owns `io.arthack.agentvoice.server`.

`scripts/install-launchagents` accepts an exact `--service` selector for install,
plan, and status operations. A selected service with changed configuration is
reloaded, a selected unloaded service is bootstrapped, and a healthy selected
service with identical rendered bytes remains running. Other manifest members
are never rendered or sent to launchctl during a targeted operation. This is
the supported deployment path for bringing up HUD without restarting
AgentVoice, the shared Portless proxy, or another fleet service.

Existing AgentBoard data, CLI, and stdio MCP access remain preserved for
historical queries. This service adds no Board import, redirect, or write path.

Evidence: `config/launchd/io.arthack.agenthud.serve.plist`,
`scripts/install-launchagents`, `tests/install-launchagents.sh`,
`tests/validate.sh`, and `skills/fleet/MAP.md`.
