# 0039: Retire the AgentLab runtime integration

Accepted September 20, 2026. Supersedes [0033](0033-supervise-agentlab-cumulative-service.md),
[0034](0034-dedicated-agentlab-codex-app-server.md),
[0037](0037-supervise-agentlab-managed-codex-launcher.md), and
[0038](0038-supervise-agentlab-fx-broker.md).

AgentLab, also known as Greybird, is now inert archived reference source rather
than an active fleet application. AgentStart no longer invokes its installer,
builds its assets, publishes the `agentlab` command, or supervises its console,
dedicated Codex app-server, or Fx broker. Removing those edges does not retire
stock Codex, AgentUsage preparation, the fxnk-owned Fx Integration install, or
any unrelated fleet job.

The three former labels move from the active manifest to the bounded retirement
list: `io.arthack.agentlab.codex-app-server`,
`io.arthack.agentlab.fx-broker`, and `io.arthack.agentlab.serve`. During the
cleanup window, exact-label or full convergence may boot out and remove only a
regular plist whose exact second-line AgentStart ownership marker matches the
label. Symlinks, foreign markers, and foreign occupants are refused. The active
templates, endpoint rendering, readiness probes, service ordering, and
Portless/deployment convergence are deleted.

Retirement preserves the AgentLab Git repository and refs, reusable source and
documentation, durable HUD history, the feedback SQLite database, and private
state. Neither AgentStart convergence nor this decision deletes those paths or
migrates them into another project. The installed command link and deployed-SHA
receipt may be removed only after the three jobs are stopped and exact ownership
is verified; AgentLab's installer has no uninstall mode.

The active fleet map contains no AgentLab runtime edge. A dated retirement note
keeps the historical boundary findable without advertising an executable path.
