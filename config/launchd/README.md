# Fleet launch agents

Every long-running fleet service on this machine is defined here and installed
by `scripts/install-launchagents`, without exception. A fleet checkout no
longer installs its own service; it ships the code, and this repository decides
when that code runs.

The machine layer keeps its own services and its own `launchd/` directory.
Namespace does not decide ownership: the exact marker does. Every service we
own still uses the same account-wide naming grammar.

## What is standardized

The frame is identical for every service, and deviating from it is a bug:

- **Label** — `io.arthack.<project>.<verb>`, matching the file name exactly.
  The final component names the action (`work`, `observe`, `serve`,
  `process-queue`), not the process shape (`worker`, `observer`, `server`,
  `daemon`).
- **Ownership marker** — the template carries exactly one standalone
  `<!-- agentstart-installer-owned: <label>.v1 -->` line. The installed marker
  must remain at that template-defined position. The installer refuses to
  unload or replace a service carrying anything else, so a hand-written or
  third-party agent that happens to share a label is never touched.
- **Tokens** — `__UPPER_SNAKE__`, replaced with XML-escaped absolute values at
  install time. Rendering fails closed: an unresolved token, a value the
  manifest does not supply, or a plist that fails `plutil -lint` aborts that
  service without publishing anything.
- **Publication** — rendered to a temporary file inside the destination
  directory, `chmod 600`, then renamed, so a reader never sees a half-written
  service. An identical rendered service that is already loaded stays running;
  convergence does not restart it.
- **`HOME` and `PATH` are always pinned absolutely.** launchd sources no shell
  rc file, so an unpinned `PATH` cannot reach uv-, nvm-, or Homebrew-managed
  tools.
- **No credential is ever rendered into a plist.** `launchctl print` discloses
  a service's environment to any process that can run it. Secrets are named by
  path and read by the process that needs them, from a mode-0600 file.
- **`Umask` 63** (`0o077`) and one log file per service at
  `~/.local/state/<tool>/<service>.log`.
- **`RunAtLoad`** — every service is expected to be correct at login.
- **Missing tool, no service.** A service whose checkout or program is absent
  is skipped, never failed, matching the rest of the AgentStart installer.
- **One executable per tool.** Every ordinary plist invokes
  `~/.local/bin/<tool>` and an explicit subcommand. Parallel `<tool>d`
  executables are not a fleet service interface. The bounded AgentVoice test
  pair is the only exception: it executes the prepared test checkout through
  Bun so a production command-link change cannot switch its source underneath
  it. ADR 0023 defines that exception and its deletion boundary.

## What is deliberately per-service

These differ because the services differ, and each template says why in a
comment beside the key:

- **`ProcessType`** — `Background` for work nobody waits on, `Standard` where a
  human is blocked on the result. Background QoS is starved first under
  contention, which is correct for ingestion and wrong for a browser a person
  is looking at.
- **Lifecycle** — the manifest names each service as `resident`, `periodic`, or
  `queue-triggered`; templates express that through `KeepAlive`,
  `StartInterval`, and `QueueDirectories`. `io.arthack.agentbrain.doctor` is
  the only periodic member and `io.arthack.agentscrape.process-queue` the only
  queue-triggered member.
- **Arguments and extra environment**, including values that must be
  discovered from another service at install time.
- **Conditional installation.** `io.arthack.agentbrain.share` installs only
  when an operator names a bind address; there is no default, by its ADR 0017.
  The AgentVoice test pair installs only while its dedicated checkout and
  dependencies are prepared.

Agentbrain's Worker can reuse a Browser profile authenticated through
Agentbrowse. Supply `AGENTSTART_INSTALL_AGENTBRAIN_BROWSER_SESSION=SESSION`
when installing to pin Agentscrape to that stable session. Subsequent installs
preserve the installed pin; an explicitly empty value clears it. The session
name is not a credential. Authentication stays in Agentbrowse's Browser profile.
Keep that session exclusive to the single resident Worker: another browser
client navigating it during extraction can change which page is read.

## Adding a service

Add the template here, add its entry to the manifest in
`scripts/install-launchagents`, and add its assertions to `tests/validate.sh`.
The plan line in `scripts/install.sh --check` comes from the manifest, so it
follows automatically.

Use `scripts/install-launchagents --install --service <exact-label>` for a
narrow convergence, with `--check` and `--status` providing the matching
read-only views. The selector accepts a current manifest label or a bounded
retirement label. It never renders, loads, or restarts a neighboring job; a
changed selected plist is reloaded, an unloaded selected plist is bootstrapped,
and a healthy identical selected job is left running.

`io.arthack.agentchats.serve` is retired. During the bounded cleanup window,
`scripts/install-launchagents --check --service io.arthack.agentchats.serve`
reports whether its old plist is absent, owned, or foreign. The matching
`--install` invocation boots out and removes only an exact-marker-owned plist;
it refuses symlinks and foreign occupants. AgentChats' CLI, OpenTUI picker,
index, and stdio MCP remain installed independently of this retired web job.

`io.arthack.agenthud.serve` keeps the durable Work view resident. It invokes
`agenthud serve`, whose default is the editable Vite/HMR view from AgentHUD's
canonical checkout and whose fixed local Portless origin is
`https://agenthud.localhost`. AgentHUD's own installer prepares the command,
dependencies, and optional production build without touching this service;
AgentStart alone owns the LaunchAgent lifecycle.

`io.arthack.agentlab.serve` keeps the current cumulative AgentLab laboratory
resident at `http://agentlab.localhost`, which the shared Portless proxy
redirects to its canonical `https://agentlab.localhost` route. It invokes the
installed `agentlab serve` contract, which rebuilds the browser UI and Node
backend together and registers that same supervised process under Portless name
`agentlab`. The command pins the internal loopback port. The template pins the
established `~/Library/Application Support/AgentLab/feedback-v1.sqlite3`
database while
leaving TypeSafe credential resolution inside the server; no credential is
rendered. Targeted status also runs `agentlab status`, so a running launchd job
is not reported healthy unless the Jev endpoint reports a coherent server-only
credential state and the SQLite feedback endpoint is ready. A missing optional
credential keeps live evaluation unavailable without failing the UI service.
The command requires the existing fleet Portless proxy and never installs or
restarts it.

`io.arthack.agentvoice.serve` independently keeps the AgentVoice transcript
reader resident at `https://agentvoice.localhost`. It invokes the public
`agentvoice serve` command with AgentVoice's configured state root and does not
operate AgentVoice's separately owned
`io.arthack.agentvoice.server`, menu app, clients, calls, or future Native SDK
shell. Exact-label convergence can replace a temporary submitted reader job;
later identical convergence leaves the canonical loaded reader running.

`io.arthack.agentvoice-test.wait` and
`io.arthack.agentvoice-test.serve` are one interim test deployment. They run
the prepared `~/worktrees/agentvoice/parallel-test-environment/agentvoice`
checkout against `~/.local/state/agentvoice/test-workspace`; the reader also
pins the `agentvoice-test` Portless name. The server's explicit workspace keeps
the default Android/network gateway disabled, and the reader stays offline if
that exact workspace socket is absent instead of falling back to production.
The jobs have separate `test-server.log` and `test-reader.log` files under the
AgentVoice state directory. An isolated installer test may override the source
checkout with `AGENTSTART_INSTALL_AGENTVOICE_TEST_CHECKOUT`; ordinary operation
uses the fixed path. Both labels wait for the pair's root and web dependencies,
including Node.js, Portless, and Vite. A rendered Git revision makes later
convergence reload a job after the test checkout advances to another commit.
Status reports that committed revision drift, and an activated service fails
convergence if its checkout or dependencies disappear.
Uncommitted edits remain development state and do not themselves trigger a
service reload.

Before first convergence, stop any foreground processes using the same test
workspace or Portless name. Then install and inspect only these labels:

```sh
scripts/install-launchagents --install --service io.arthack.agentvoice-test.wait
scripts/install-launchagents --install --service io.arthack.agentvoice-test.serve
scripts/install-launchagents --status --service io.arthack.agentvoice-test.wait
scripts/install-launchagents --status --service io.arthack.agentvoice-test.serve
```

An absent test label is skipped during ordinary full convergence. Its exact
selector is the first-activation gate; once installed, later full convergence
keeps that label current. This lets the foreground owner hand off each process
without a routine install claiming it first.

Removing or replacing this proof means retiring both labels, templates, fixed
checkout wiring, tests, glossary text, ADR references, and fleet-map edges
together. A future multi-session AgentVoice server supersedes the pair rather
than growing a registry or session selector in AgentStart.

`io.arthack.agentstart.watch-config` is a resident configuration watcher. It
invokes `agentstart config watch --notify`, reconciles filesystem events and
a 30-second fallback, and uses Funk notifications. Its [one-way preference
contract](../harness-preferences.md) forbids writing authored preferences.
