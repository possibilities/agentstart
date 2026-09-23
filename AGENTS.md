# AgentStart agent guidance

Read [CONTEXT.md](CONTEXT.md) for the fleet's terms and the relevant
[decision records](docs/adr/) before changing ownership or convergence.

## Repository context

- `~/code/agentstart` owns AI-toolchain installation for this machine. The
  machine layer itself — Homebrew, Stow, launchd, macOS settings, account
  migration — is owned elsewhere and is not this repository's concern; its
  installer invokes this checkout, and that call is the whole relationship.
  When a change straddles the two, the scope test decides: depended on by or
  deeply related to the fleet → here; the machine itself → not here. Every
  path here resolves from `$HOME` — nothing may assume a particular account
  name.
- The fleet lives beside this checkout: every `~/code/agent*` checkout
  without exception — including `~/code/agentguidance`, the general guidance
  skills and their renderer. AgentUsage owns Claude/Codex/Grok account
  storage and observation, plus Claude/Codex preparation and the shared proxy. Each
  fleet repo owns its own hardened installer and exports its own skills; AgentStart invokes
  contracts, it does not reach inside — but it decides that every
  one of them is installed. `install-agent-clis` runs each checkout's own
  installer, and `config/launchd/` defines AgentStart-owned fleet services;
  the explicit exceptions below have their own service owner. Two owners
  would race to render the same service. A fleet checkout
  ships the code; this repository decides that it is present and when it
  runs. AgentBrowse is also a service-ownership exception: its explicit
  `scripts/install-host` owns Hypeman installation and service recovery on both
  Mac and Linux. AgentStart must not render a competing Hypeman service.
  AgentVoice is the explicit exception: its approved default-server
  topology makes `agentvoice/scripts/install.sh --install` the sole owner of
  `io.arthack.agentvoice.server`, including plist rendering and service lifecycle.
  AgentStart delegates to that installer and must not add a competing template
  or registration. That exception covers the default voice server only. As a
  bounded interim test environment, AgentStart owns
  `io.arthack.agentvoice-test.wait` and `.serve`, which execute the dedicated
  AgentVoice test checkout with one explicit isolated workspace and one named
  reader; they never claim the default endpoint. AgentStart also owns
  the separate `io.arthack.agentvoice.serve` transcript-reader LaunchAgent
  through AgentVoice's installed `agentvoice serve --production --tailscale`
  contract. Bare direct `agentvoice serve` remains editable for development.
  AgentStart also owns the separate `io.arthack.agenthud.serve` web-view
  LaunchAgent through the independent
  AgentHUD checkout's installed `agenthud serve` contract.
  AgentStart owns the direct MCP resource inventory used by
  managed Claude, Codex, and AgentVoice sessions. Gog owns its Google credentials;
  AgentStart installs Gog and binds each declared mailbox at MCP startup.
  Nothing outside these installer contracts installs a fleet component.
- Outside projects are Clones under `~/source/<upstream-owner>--<repo>`, with
  the original repository as `upstream` and our optional fork as `fork`.
  Managed fork dependencies bind their `integration` branch — every patch
  carried, merged, and the only ref an installer builds.
  A patch offered upstream lives on its own branch beside it. Claude/Codex
  swap tools are no longer fleet installer dependencies. AgentUsage's observer/proxy service
  converges last. Old checkouts, credentials and backups are preserved.
  Fx's fork lifecycle and integration installer are owned by
  `~/code/fxnk`; AgentStart invokes `fxnk/scripts/install.sh --install --sha`
  with its tracked, ship-gate-approved Integration pin as the harness
  installation contract instead of reaching into
  `~/source/vercel-labs--fx`. fxnk installs
  that exact source build to `~/.local/bin/fx` and disables Fx's independent
  auto-updater. Both fork owners refuse a checkout whose fork remote is not
  ours. The `fork-rebase-policy` wiki page is the contract.
- Herdr comes from the official stable Homebrew formula and must speak fleet
  protocol 20 or newer. `scripts/herdr-socket-state` checks every default and
  named server socket before Homebrew may change the installed client bytes.
  A missing formula installs once the sockets are proved inactive. An existing
  formula upgrades only during an explicitly authorized inactive maintenance
  run with `AGENTSTART_HERDR_ALLOW_UPGRADE=1`. A present socket or uncertain
  state defers either operation. Package-manager updates cannot use Herdr's
  live handoff, so never weaken that gate around resident agents.
- Fleet repository guidance identifies the shared owners that apply there:
  the skill scan and its cadence, this repository's fleet map, and
  AgentGuidance's general doctrine. When a shared convention changes, update
  the affected entrypoints together. A short pointer is sufficient; do not
  require identical footers or copy irrelevant instructions into small projects.

## Fix-forward installation

Every durable AI-stack change belongs in this repository and converges by
rerunning `scripts/install.sh --install`. Do not hand-configure the live
machine, and do not grow a second installer or synchronization path here or
in `~/code/agentguidance`.

The default convergence interface is exactly `scripts/install.sh` (`--install`,
`--check`), `scripts/sync-skills` (`--check`), and
`scripts/install-harness-shims`. The explicit operator-run
`scripts/install-agentvoice-android --install` is separate: it delegates a
phone proof deployment to AgentVoice's checkout-owned installer and must never
be called by those default install or synchronization paths. The machine's
installer and scheduled updater call these by path with fixed semantics: a missing optional fleet
checkout is a skip inside the script, a present-but-broken one fails, and
the updater path (`sync-skills`) must stay unattended-safe
— no sudo, no uninstalls, no application restarts. Machine migrations are
bounded maintenance work, not permanent phases of either installer. That
caller's own test suite greps these scripts, so renaming or resemanticizing
them breaks it.

Where things go:

- A new AI tool, harness configuration, npm global, or external skill pack:
  `scripts/install.sh`, with its plan line in the `--check` output and
  assertions in `tests/validate.sh`.
- An agent-facing workflow: classify its authoritative surface using
  `docs/agent-interfaces.md`. Prefer an existing typed MCP for structured
  remote actions, the harness's native mechanism for orchestration and
  approvals, and the owning CLI/TUI for interactive or local workflows. Do
  not add an MCP solely to make every skill name map to one.
- Personal Codex preferences are the authored-source exception:
  `~/code/funk/config/harnesses/codex.toml`. AgentStart still owns installation
  and the invocation profile (`scripts/codex-invocation`), invoked by its Codex
  shim after account selection. Never link the live config to Funk or copy
  trust/auth/plugin state into the authored file. `config/codex/README.md`
  defines precedence, cleanup, bypasses, and the native-profile contract.
- Smolmux installation: invoke `~/code/smolmux/scripts/install.sh --install`.
  Smolmux owns that consumer path, the editable `smolmux` command, its pinned
  Companion, and doctor verification. AgentStart owns only fleet ordering and
  the shared install directory; Smolmux sessions run arbitrary commands and
  have no Fx pin or agent-specific MCP command.
- AgentVoice network access: `bun scripts/agentvoice-network.ts --enable` explicitly
  configures a dedicated tailnet-only Serve endpoint. Default installation runs
  its `--install` convergence only for already enabled network settings, using
  AgentVoice's public network/status/configure and service/restart commands.
  Never grant credentials, enable Funnel or replace foreign routes at install time.
- AgentVoice Android proof deployment: invoke
  `scripts/install-agentvoice-android --install`. It resolves AgentVoice under
  the common fleet root and delegates only to
  `agentvoice/scripts/install-android --install --host <host>`; AgentVoice owns
  the build, transport, remote validation, and installation contract. The
  default host is `smolbird`, overridden by
  `AGENTSTART_AGENTVOICE_ANDROID_HOST`. This remains an explicit operator action
  and is never part of `install.sh`, `sync-skills`, or `install-agent-clis`.
- A new fleet tool: add the checkout to the `install-agent-clis` loop if it
  has a CLI installer, and note the ordering constraint in the comment there
  if it has one. The `agent*` skills scan needs nothing. A loop member's
  installer must be rerunnable, because a present checkout that fails stops
  the whole install.
- AgentHUD is an ordinary independent fleet checkout under `~/code/agenthud`.
  Its `scripts/install.sh --install` owns the editable command, dependencies,
  and production assets without service effects. `install-agent-clis` invokes
  that contract directly. AgentStart separately owns the resident HUD
  LaunchAgent; no AgentVoice installer or redirect sits between them.
- AgentLab is retired from the active fleet and preserved as archived reference
  source. AgentStart does not install its command, build its assets, supervise
  its Codex or Fx daemons, or publish its Portless route. The three former exact
  labels remain temporarily selectable only for bounded exact-marker cleanup;
  the retirement preserves AgentLab's source history, durable records, feedback
  database, and state rather than adopting them into another project.
- A fleet CLI's self-description: one contract per CLI, published as
  `<cli> guide --json` against `config/agent-contract/schema.json`, with
  `--agent-help`, `--agent-teaser`, and `--help` rendered from it rather than
  written again beside it. `config/agent-contract/README.md` is the contract;
  `scripts/validate-agent-contract.ts` enforces it. Each command declares its
  own `audience` and `mutates`, so the CLI's owner — not a downstream consumer
  — decides which verbs are for agents. A second hand-written agent help is
  the failure mode this replaces, not a fallback it tolerates.
- A new long-running fleet service: a verb-named template in `config/launchd/`,
  an entry with its explicit lifecycle (`resident`, `periodic`, or
  `queue-triggered`) in the manifest at the top of
  `scripts/install-launchagents`, and assertions in `tests/validate.sh`.
  `config/launchd/README.md` is the
  contract — what every service shares and what is deliberately
  per-service. Labels use `io.arthack.<project>.<verb>`; the exact ownership
  marker, not the namespace, decides what this installer may replace.
  Use `scripts/install-launchagents --<mode> --service <label>` when one service
  must be checked, diagnosed, or converged without touching its neighbors.
  The replaceable AgentVoice test pair is the one source-checkout exception to
  the installed-public-command rule; ADR 0023 keeps its fixed checkout,
  workspace, origin, two labels, and eventual deletion as one boundary.
- A fleet TUI bound to a Herdr popup: always add a pane entrypoint to the
  `agentsurface` plugin, then bind the key to `herdr plugin pane open`. The
  tool continues to own its TUI; the shared plugin owns the popup title and
  geometry so the dialog is also exposed through Herdr's plugin surface.
- A statusline change: `config/statusline/`, converged by
  `scripts/install-statusline`. One bar in two harness idioms, because that is
  all the harnesses offer — Claude runs a render command per frame, while
  Codex draws its own bar and only lets an operator choose and order a fixed
  set of items. A field added to one renderer belongs in the other wherever
  it can know it; each renderer's comments record what its harness cannot.
- An operator extension prompt edit: `prompts/agentguidance/`, then
  `scripts/install.sh --install` (or wait for the six-hour sync plus the
  next render) so the rendered skills pick it up. A GUIDELINES.md bullet
  is a rule plus, when detail exists, the named wiki contract page
  (`fork-rebase-policy`, `document-placement-policy`, `fleet-tui-design`)
  — never the detail itself, which lives in the page and is read at the
  trigger. These lines render into collab, build, and maintain. Skill names
  and descriptions provide capability discovery; do not add a second tool
  catalog to prompts. Standing tool preferences belong in GUIDELINES.md;
  `agentwiki get tool-advertisement-policy` records that boundary.
- A cross-project decision that belongs to no single repo: the wiki
  (`agentwiki new`), one page per subject, wikilinked to its neighbours
  and pointed at from wherever it constrains. `tool-advertisement-policy`
  is the standing example.
- A change in who calls what between fleet apps: update the map the
  `fleet` skill serves (`skills/fleet/MAP.md`) in the same change.

## Skills

AgentStart owns `roles/default`: prompt Markdown and its complete MCP inventory.
`scripts/render-roles` assembles it through the normal resource sync and safely
retires intact AgentStart-owned `manager` and `worker` outputs. Changing the
common inventory does not automatically change the role roster. The default role
omits the Attention, Chats, Grok, HUD, Keys, Mux, Sounds, and Surface MCPs while
keeping the HUD skill and CLI-backed recording responsibility. Managers record
native worker reports under their own actor; there is no separate worker role.
Preserve this boundary through explicit-role launch rendering. See
[the default-role cutover](docs/adr/0040-collapse-explicit-roles-to-default.md).

This checkout participates in the same convention it administers: active skills
under `skills/<name>/SKILL.md` ship into the fixed private fleet resources via
`scripts/sync-skills`. Bare permission shims do not load them; explicit
roles can expose `/agent:<name>` in Claude Code and `$agent:<name>` in Codex. The
`fleet` skill is the dependency map of the ecosystem;
its `MAP.md` claims to be current, so a stale edge there is a bug, not a doc
nit. The explicit Board cutover exception prunes only `board` and `groom` from
the owned resource tree while preserving AgentBoard's checkout, command, data,
history, and stdio MCP implementation for legacy queries. Current AgentBoard
has no socket service endpoint.

## Validation

For document changes, run `python3 scripts/check-project-docs.py` against each
affected checkout. See [document integrity](docs/project-memory.md) for its
scope, advisory warnings and explicit exceptions. Shared guidance changes also
need the owner's rendering checks and installed-output convergence.

```sh
tests/validate.sh
```

After changing installation behavior, also run
`scripts/install.sh --install` and compare the installed `collab` manifest
with its agentguidance source template — the same convergence check the
fleet's guidance prescribes. `AGENTS.md` is the sole repository guidance
entrypoint.
