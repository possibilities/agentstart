# 0019: Use AgentVoice graceful menu convergence

Accepted September 15, 2026. The operator requested that AgentStart use
AgentVoice's supported graceful menu-update flag during full convergence.

## Decision

Default `install-agent-clis` convergence invokes the AgentVoice checkout's
installer with `--install --quit-menu`. When the installed owned menu app is
outdated and running, AgentVoice verifies its identity and supported control
protocol, asks that exact instance to quit through its private busy-gated
endpoint, waits boundedly, atomically replaces the bundle, and reopens it only
because it was previously running. Current and stopped menu apps retain their
presence. Refusal, incompatible legacy state, uncertain exit, publication
failure, or relaunch failure remains visible and fails convergence according to
AgentVoice's owner contract.

`AGENTSTART_PRESERVE_AGENTVOICE_SERVICE=1` continues to select AgentVoice's
`--command-only` scope instead. That live-call cutover operates neither the menu
nor the waiting-server LaunchAgent. The six-hour `sync-skills` path remains
unchanged and performs no application lifecycle operation.

## Consequences

A normally running supported menu app no longer turns an explicit full machine
convergence into a manual quit-and-rerun sequence. AgentStart supplies only the
owner-defined opt-in; it does not inspect processes, send signals, implement a
second app controller, answer UI questions, or weaken AgentVoice's identity and
busy checks. Full AgentVoice installation retains its existing service lifecycle,
including the separate live-call preservation override.

Fixture tests pin both branches of the delegation. The installer plan, README,
and fleet map expose the lifecycle boundary and distinguish it from unattended
skill synchronization.
