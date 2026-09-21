# 0022: Supervise the AgentVoice transcript reader in AgentStart

Accepted September 15, 2026. Refined September 20, 2026 to make the resident
reader a production deployment. The human wants the AgentVoice transcript
reader continuously available at its fixed local origin across AgentVoice
runtime restarts and login without retaining Vite's development module graph in
the long-lived process.

AgentStart owns `io.arthack.agentvoice.serve`, a resident user LaunchAgent that
invokes the installed public command as `~/.local/bin/agentvoice serve
--production --tailscale`. AgentVoice continues to own that foreground command,
the fixed Portless route `https://agentvoice.localhost`, and all transcript and
composer behavior. A bare direct `agentvoice serve` remains AgentVoice's
editable Vite development surface; production mode is a deployment choice of
this one resident job. The job follows the fleet service frame: exact ownership
marker, private combined log under AgentVoice state, pinned `HOME` and `PATH`,
the configured `XDG_STATE_HOME` or its documented default, login start,
keep-alive policy, standard process priority, and throttled retry.

Full AgentStart convergence invokes AgentVoice's checkout-owned installer
through `install-agent-clis` before `install-launchagents`. That owner contract
prepares `web/dist` before AgentStart renders or loads this production reader;
a failed AgentVoice installation stops convergence before launchd can adopt a
job whose production assets are absent. The fixed test reader remains an
editable source-checkout service and does not inherit `--production`.

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
