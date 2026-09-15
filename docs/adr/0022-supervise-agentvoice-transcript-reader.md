# 0022: Supervise the AgentVoice transcript reader in AgentStart

Accepted September 15, 2026. The human wants the AgentVoice transcript reader
continuously available at its fixed local origin across AgentVoice runtime
restarts and login.

AgentStart owns `io.arthack.agentvoice.serve`, a resident user LaunchAgent that
invokes the installed public command `~/.local/bin/agentvoice serve`. AgentVoice
continues to own that foreground command, its editable Vite reader, the fixed
Portless route `https://agentvoice.localhost`, and all transcript and composer
behavior. The job follows the fleet service frame: exact ownership marker,
private combined log under AgentVoice state, pinned `HOME` and `PATH`, the
configured `XDG_STATE_HOME` or its documented default, login start, keep-alive
policy, standard process priority, and throttled retry.

This reader lifecycle is independent of AgentVoice's
`io.arthack.agentvoice.server` waiting voice server. AgentVoice remains the sole
owner of that server LaunchAgent and its native runtime. Installing or restarting
the reader neither starts a call nor operates the server, the menu app, a client,
or a future Native SDK shell. Closing or replacing the reader leaves an active
call running.

`scripts/install-launchagents --install --service
io.arthack.agentvoice.serve` is the supported narrow convergence path. It can
replace the known temporary submitted job at the same exact label, then future
identical convergence leaves the canonical loaded job running. The matching
`--check` and `--status` forms inspect only this service.

Evidence: `config/launchd/io.arthack.agentvoice.serve.plist`,
`scripts/install-launchagents`, `tests/install-launchagents.sh`,
`tests/validate.sh`, and `skills/fleet/MAP.md`.
