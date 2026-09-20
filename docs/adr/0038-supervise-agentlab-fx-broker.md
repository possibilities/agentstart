# 0038: Supervise AgentLab's persistent Fx broker

Superseded by [0039](0039-retire-agentlab-runtime-integration.md).

Accepted September 20, 2026. AgentLab's Fx adapter requires one reconnectable
ACP owner whose lifetime is independent of the console, while browser and
console processes must not own native Fx children.

AgentStart owns the resident `io.arthack.agentlab.fx-broker` LaunchAgent. It
enters through the installed `agentlab fx-broker --listen
unix:///absolute/socket` contract and converges before
`io.arthack.agentlab.serve`. AgentLab owns the broker implementation, Fx child
lifecycle, generation identity, catalog discovery and bounded replay. The
console receives the exact installed broker endpoint in `AGENTLAB_FX_ENDPOINT`;
the browser receives only normalized capabilities and catalog values.

The default endpoint is
`~/.local/state/agentlab/fx-acp-broker.sock`. A socket override selects desired
state only while the broker itself is converged. Console-only convergence and
all status operations read the exact owned broker plist, matching the existing
Codex desired-versus-installed rule. Status is deliberately observational: a
running job is ready only when its Unix socket and regular identity manifest
are owner-only and the bounded manifest validates, without opening a lease,
starting an ACP candidate or submitting a
provider prompt.

The plist contains only the installed AgentLab command, fixed endpoint, HOME
and PATH. It carries no credential or provider configuration. Its combined
private log is `~/.local/state/agentlab/fx-broker.log`; AgentLab suppresses Fx
child output. Exact-label convergence refuses foreign ownership and leaves an
identical healthy loaded job running.

A broker restart changes generation identity because native sessions and replay
journals were lost. Rollout therefore prepares AgentLab first, converges and
checks the Codex daemon and Fx broker, then converges or restarts the console.
No AgentVoice, shared Portless, fxnk, Fx Integration pin or credential owner is
changed by this service.
