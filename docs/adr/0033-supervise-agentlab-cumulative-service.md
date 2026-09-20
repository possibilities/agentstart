# 0033: Supervise the cumulative AgentLab service

Superseded by [0039](0039-retire-agentlab-runtime-integration.md).

Accepted September 19, 2026. The human wants AgentLab's current cumulative UI
and backend installed as one reliable local service while AgentLab's experiment
repository continues to own its application code, credential boundary, and
feedback state.

The later Fx endpoint and service ordering are recorded in
[0038](0038-supervise-agentlab-fx-broker.md).

AgentStart owns `io.arthack.agentlab.serve`, a resident user LaunchAgent that
invokes the installed public command `~/.local/bin/agentlab serve`. AgentLab's
own hardened installer prepares frozen dependencies, builds the cumulative
client and server, publishes that command, and records its deployed commit
without touching service state. There is no second service owner.

The command pins Portless name `agentlab`, uses the existing shared HTTPS proxy,
and keeps its backend on loopback port 4177. Requests to
`http://agentlab.localhost` follow Portless's TLS redirect to the canonical
`https://agentlab.localhost` UI and same-origin API. The service also pins the
established macOS feedback path
`~/Library/Application Support/AgentLab/feedback-v1.sqlite3`. TypeSafe
environment or Keychain lookup remains inside that server, and no credential
is rendered into the plist. The job uses AgentStart's exact ownership marker,
private combined log at `~/.local/state/agentlab/server.log`, login start,
resident keep-alive, standard process priority, private umask, and throttled
retry.

`scripts/install-launchagents --check|--install|--status --service
io.arthack.agentlab.serve` is the isolated lifecycle surface. A changed plist
is reloaded, an identical healthy job remains running, and no neighboring
service is rendered or operated. Status requires both a running launchd job and
a successful read-only `agentlab status` probe of the Jev credential state and
feedback readiness endpoints. A missing optional credential is a coherent
unavailable state rather than a failed UI service.

AgentLab requires the fleet's existing shared Portless proxy. Neither the
AgentLab command nor this LaunchAgent installs, starts, stops, or restarts that
proxy, so AgentStart does not create a second proxy owner.

Evidence: `config/launchd/io.arthack.agentlab.serve.plist`,
`scripts/install-agent-clis`, `scripts/install-launchagents`,
`tests/install-agent-clis.test.ts`, `tests/install-launchagents.sh`,
`tests/validate.sh`, and `skills/fleet/MAP.md`.
