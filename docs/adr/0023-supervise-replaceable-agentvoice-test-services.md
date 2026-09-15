# 0023: Supervise replaceable AgentVoice test services

Accepted September 15, 2026. The human wants the isolated AgentVoice test
server and named transcript reader to survive process failures and login while
the production server, reader, menu, call, workspace, origin, and network
gateway remain unchanged.

## Decision

AgentStart owns two resident user LaunchAgents as one bounded interim
deployment:

- `io.arthack.agentvoice-test.wait` runs the prepared
  `~/worktrees/agentvoice/parallel-test-environment/agentvoice` checkout with
  `server --workspace ~/.local/state/agentvoice/test-workspace`.
- `io.arthack.agentvoice-test.serve` runs that same checkout with
  `serve --workspace ~/.local/state/agentvoice/test-workspace --name
  agentvoice-test`, serving `https://agentvoice-test.localhost`.

The services use separate logs and the ordinary ownership, publication,
resident lifecycle, status, and exact-label convergence frame. First activation
requires each exact service selector; an ordinary full install skips an absent
test label, then converges it after that label has been installed. This keeps a
routine install from racing the foreground proof during the ownership handoff.
Installation prepares the workspace directory and skips both halves until the
test checkout, root dependencies, Node.js, Portless, and Vite are available.
The rendered source revision makes later convergence reload a resident job when
the checkout advances to a different commit, and status reports that drift
until convergence. Missing prerequisites remain an optional skip only before a
label is activated; an installed label fails convergence instead of leaving an
unmaintainable job silently registered. The fixed source checkout is a
deliberate exception to the normal installed-command rule: using
`~/.local/bin/agentvoice` would follow the production editable link and could
silently switch the test deployment's code.

AgentVoice's existing command contract supplies the isolation. An explicit
server workspace uses its hashed endpoint and does not start the default
Android/network gateway. The reader watches that same explicit endpoint and
does not fall back to the default socket. The production labels remain
`io.arthack.agentvoice.server` and `io.arthack.agentvoice.serve`; AgentStart
still never renders or operates the former.

Before the first canonical convergence, the owner of any foreground test
server or reader must stop those exact processes so two owners do not contend
for the workspace socket or `agentvoice-test` Portless name. This record does
not authorize stopping them.

## Supersession boundary

This is not an AgentStart multi-session abstraction. There is one fixed source
checkout, one test workspace, one named reader, and two labels. No registry,
endpoint discovery, arbitrary workspace selection, or second production server
is introduced.

A future AgentVoice multi-session server may supersede this proof behind
AgentVoice's verified workspace, controller, and thread identity. That change
retires both test labels and removes their templates, manifest entries, fixed
checkout wiring, tests, documentation, and fleet-map edges as one unit.

The `wait` action label names the service's behavior while its public AgentVoice
subcommand remains `server`; it does not add a second server executable.

Evidence: `config/launchd/io.arthack.agentvoice-test.wait.plist`,
`config/launchd/io.arthack.agentvoice-test.serve.plist`,
`scripts/install-launchagents`, `tests/install-launchagents.sh`,
`tests/validate.sh`, AgentVoice's `docs/parallel-test-environment.md`, and
`skills/fleet/MAP.md`.
