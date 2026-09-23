> *Slop Made With Sweat: Made with a lot of love by someone who loves code but read none of it.*

# AgentStart

[![CI](https://github.com/possibilities/agentstart/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/possibilities/agentstart/actions/workflows/ci.yml)

AgentStart is the AI half of this machine: the installer and home for
everything the agent fleet in `~/code` depends on. The machine layer —
Homebrew, Stow, launchd, macOS settings — is owned separately and calls into
this checkout for the rest. The boundary rubric is one sentence:

> Depended on by, or deeply related to, the agent\* fleet → AgentStart.
> Otherwise → the machine layer, and not this repository's concern.

This is one operator's machine layer, published as working reference beside
the agent* fleet it installs. It is orderly — contracts, tests, recorded
decisions — and deliberately opinionated: the judgment calls stay in, stated
plainly, rather than generalized away.

If you are not that operator: the platform is macOS, every path resolves from
`$HOME`, and the installers drive sibling checkouts under `~/code` — the
agent* fleet and `agentguidance` for the general skills, with the machine's
own installer calling in. A checkout you do not have is a skip, not a
failure.
A vendor CLI installs by its own official installer, which reaches the
network. Run `scripts/install.sh --check` to see the whole plan before
believing any of this.

## Layout

- `scripts/` — the installers the machine invokes; the whole external
  interface.
- `prompts/` — the operator guidance the installer links into the home:
  - `agentguidance/` — the extension prompts `SYSTEM.md` and `GUIDELINES.md`,
    which agentguidance renders into collab, build, and maintain.
    Linked into `~/.config/agentguidance/`. Skills are discovered through
    their names and descriptions; there is no separate tool catalog.
  - `AGENTS.md` — the deliberately empty harness guidance source, copied into
    the fixed private resources and linked from there to `AGENTS.md` in the
    Claude Code and Codex global directories. Advice belongs in the extension
    prompts.
- `config/` — harness configuration and resource manifests, the
  agent-browser, Herdr, and smolmux operator configs, and the launchd templates for
  fleet services AgentStart owns.
- `skills/` — skills this checkout exports through the agent* scan, like any
  other fleet repo. `fleet/` is the dependency map of the whole ecosystem.
- `tests/validate.sh` — the assertions; run it before committing.

Cross-project decisions and policy live in the wiki, not here — the
`tool-advertisement-policy` page (`agentwiki get <slug>`).

## Contracts

The machine's installer relies on exactly these entry points; their paths,
flags, and skip-versus-fail semantics are load-bearing:

- `scripts/install.sh --install` — the whole AI toolchain, each piece by its
  own checkout's contract, skipping checkouts that are absent:

  - Claude Code and Codex, by their official installers; Pi as a bare CLI from
    the explicit npm action published by its upstream installer, without that
    installer's choice menu, fleet resources, or integration; plus the
    official Homebrew cask for the standalone Grok Build CLI/TUI (without
    Herdr integration yet);
  - Gog through its Homebrew formula, with separate MCP registrations for the
    two declared Gmail accounts and Google-owned sign-in;
  - Zig (an intentional duplicate of the machine's Brewfile), `llm`, the
    pinned Plannotator review CLI with its managed agent-terminal runtime and
    version-matched core skills, and the Homebrew-installed Hunk review TUI
    with its version-matched bundled skill;
  - smolmux's repository-owned source installer and pinned Companion, plus the
    generated live Herdr config and linked smolmux key config;
  - the current released `@native-sdk/cli` and pinned `agent-browser` npm globals, plus the
    linked ordered agentbrowse deployment and provider configs backed by
    `agentbrowse provider`;
  - individual fleet MCPs including AgentHUD, Agentdesk, termctrl, agent-browser, account-bound Gog,
    and the fleet-owned shadcn registry through one shared resource inventory;
  - the `~/.claude/AGENTS.md` and `~/.codex/AGENTS.md` guidance links;
    the extension prompt links;
  - the external skills and fixed private fleet resources;
  - the agentwiki, archival agentboard, agentbrowse-infra, agentbrowse,
    agentattention, agentsearch, agentkeys, agentusage, and
    agentgrok, and independent agenthud CLIs;
  - AgentUsage’s owned Claude/Codex accounts and single proxy through its
    existing observer daemon; enroll/import accounts before switching balanced
    consumers, then converge the service after AgentUsage.
    No Claude/Codex swap checkout or command is an installation prerequisite;
    existing checkouts, backups and credentials are preserved;
  - agentchats' CLI, index, OpenTUI picker, and MCP; the fleet launch agents;
    and finally `sync-skills`.

  The machine's installer calls this and refuses to finish without it.
  `--check` prints the plan without changing anything.
- `scripts/install-launchagents --install --service io.arthack.agenthud.serve`
  — converge only the resident editable HUD at
  `https://agenthud.localhost`. The same selector works with `--check` and
  `--status`; a healthy unchanged job is not restarted. AgentHUD's own installer
  prepares its editable command, dependencies, and assets first, without
  managing this or any other service.
- `scripts/install-launchagents --install --service io.arthack.agentvoice.serve`
  — converge only the resident AgentVoice transcript reader at
  `https://agentvoice.localhost`. The matching `--check` and `--status` forms
  inspect only that label; this path does not operate the separately owned
  AgentVoice waiting server, menu app, clients, or calls.
- `scripts/install-launchagents --install --service io.arthack.agentvoice-test.wait`
  and `--service io.arthack.agentvoice-test.serve` — after any foreground test
  processes have been stopped, converge the isolated test server and the named
  reader at `https://agentvoice-test.localhost`. Both run the prepared
  `~/worktrees/agentvoice/parallel-test-environment/agentvoice` checkout against
  `~/.local/state/agentvoice/test-workspace`; the matching `--check` and
  `--status` forms stay exact-label. These are replaceable interim services and
  never operate the default server, reader, menu, call, or network gateway.
  Absent labels are skipped by ordinary full convergence; each exact selector
  is the deliberate first-activation path after its foreground owner exits.
- `scripts/sync-skills` — the cheap convergence path: the active agent* checkout
  scan into `~/.local/share/agentstart/resources`, followed by harness render
  refresh. The scheduled updater calls this every six hours. It
  removes the retired Board and Groom copies only from its owned private
  resources and never restarts services.
  `--check` prints the plan and, when rendered roles and AgentRoles are present,
  audits the installed Codex default-role skill copy without changing it.
- [`docs/agent-interfaces.md`](docs/agent-interfaces.md) — the policy and
  support matrix for MCP, native harness, and CLI/TUI workflows. A workflow
  needs one authoritative surface; an MCP wrapper is not required when the
  harness or interactive tool already owns the contract.
- `scripts/install-harness-shims` — permission-default shims for bare
  `claude`/`codex`. The same entrypoint installs the `~/.local/bin/terminal-notifier`
  router for AgentNotify only, refusing installation while Homebrew
  terminal-notifier remains linked. If AgentNotify is unavailable, the router
  fails without submitting elsewhere. The full installer also converges them.
  The shims do not select accounts, profiles, models, skills, or MCPs.
- `scripts/install-agentvoice-android --install` — an explicit phone proof
  deployment, intentionally outside every default convergence path. It
  delegates to the sibling AgentVoice checkout's `scripts/install-android`
  contract with host `smolbird`, or
  `$AGENTSTART_AGENTVOICE_ANDROID_HOST` when set. AgentStart selects the fleet
  checkout and host; AgentVoice owns building, reaching the ADB host, and
  validating the installed runtime.
General-purpose AI desktop clients are not here by design: the Claude and
ChatGPT casks belong to the machine layer, as does the `gh` credential
migration. Grok Build is its CLI-only cask exception.

AgentStart renders [one MCP inventory](config/resources/mcp-servers.json) into
the private shared resources. Explicit roles and AgentVoice can load it;
AgentVoice's prepared default role links the same file. Discovery happens in
the MCP host, without a repository scan at launch. AgentStart exposes no HTTP
projection of this inventory. Shadcn retains project cwd. Grok Build remains
outside the permission shims and Herdr.

For a full install while a voice call is active, set
AGENTSTART_PRESERVE_AGENTVOICE_SERVICE=1. This uses AgentVoice's supported
--command-only installer mode; the prepared role applies to subsequent calls.
Otherwise full convergence passes `--quit-menu`: an outdated running owned menu
app is asked to quit gracefully, updated, and reopened only if it was previously
running. A current or stopped menu keeps its presence unchanged, and a refusal
still fails the install without replacing the app. The six-hour `sync-skills`
path never performs this lifecycle operation.

To deploy the experimental Android browser/Termux proof separately, run:

```sh
scripts/install-agentvoice-android --install
```

Set `AGENTSTART_AGENTVOICE_ANDROID_HOST` to select a host other than
`smolbird`. This command is deliberately absent from `install.sh`,
`install-agent-clis`, and `sync-skills`; phone deployment is never an
unattended convergence side effect.

## Herdr and Ghostty color

There is no theme manager. Ghostty runs its built-in default colors, Herdr's
`terminal` theme follows whatever the terminal shows, and tmux styles its
chrome with ANSI indices that resolve the same way. No layer names a color of
its own, so the terminal is the only place a palette could ever be set.

`scripts/herdr-config install` renders AgentStart's tracked behavior config
into `~/.config/herdr/config.toml`, checks the candidate with `herdr config
check`, atomically replaces the live file, and asks a running server to reload.
It is rendered rather than linked because Herdr writes its own keys into that
file, and neither checkout may become program-written state.

Until Herdr's Codex integration advances past v8,
`scripts/install-herdr-codex-session-fallback --install` also converges a
temporary `SessionStart` identity bridge at its existing trusted hook path.
It runs only inside Herdr, uses Herdr's public
`pane report-agent-session` command, and self-disables for newer integration
versions. The dedicated installer has an explicit `--uninstall` retirement
path; no Herdr source patch is installed.

Smolmux installs through `~/code/smolmux/scripts/install.sh`, its canonical
consumer path. Smolmux owns the editable `smolmux` command, pinned Companion,
and doctor check. It runs arbitrary commands and no longer owns an Fx pin,
`smolmux-fx`, or an agent-specific MCP command. A machine without the smolmux
checkout skips it.

`scripts/smolmux-config install` links `config/smolmux/config.toml` into
`~/.config/smolmux/config.toml`. smolmux does not write that file, and its `[keys]`
schema is a strict subset of Herdr's; both operator configs use `ctrl+space` as
their prefix.

`scripts/agentmux-config install` links `config/agentmux/instances/default.yaml`
into `~/.config/agentmux/instances/default.yaml`: the default agentmux instance's
config, in agentmux's grammar: the prefix, the harness defaults, the setup
(`~/code/agentwork`, whose `bin/tray` is the agent list), and a section per
configured Panel saying which program runs there and its visibility wish. The
agent-list program ships its own identity; AgentMux automatically keeps that
Panel hidden with no Agents, reveals it with the first and hides it after the
last. This is product behavior, independent of the personal `needs-agents` flag.
AgentMux reads Config at start or explicit `config.apply` and never writes it. agentmux and agentwork install in the fleet CLI loop; agentwork
puts nothing on PATH.

`scripts/agentbrowse-config install` links the version-2 Hypeman deployment:
Artbird first, local Mac second. AgentBrowse's explicit `scripts/install-host`
owns runtime dependencies and automatic service recovery on each host. Its
private connection files must exist before linking this policy. Browser launch
never installs infrastructure or acquires an image.

The same file locks the Live View video capture policy. The shared
`browser.video` policy keeps Chromium's display at 60 Hz and captures 30 VP8
frames per second; only Artbird overrides it to 60 fps, 4,792,320 bits/s, and a
60-frame keyframe interval, the shape agentbrowse measured for a remote browser
backend. The local Hypeman backend deliberately carries no override and stays on the
shared policy until that shape is validated locally. Agentbrowse verifies
capture settings as part of target ownership, so after the policy changes it
rejects an existing Browser target at its next launch or `create` until that
target is destroyed and recreated explicitly; `list`, `resolve`, and `view`
keep working, and Browser profiles, cookies, and authentication are preserved.

`scripts/agent-browser-config install` links
`config/agent-browser/config.json` into `~/.agent-browser/config.json`. It
selects agentbrowse and registers the managed
`~/.local/bin/agentbrowse provider` command as the short-lived
`browser.provider` plugin. It resolves that link through `$HOME`, not `PATH`,
so an older Bun-global command cannot shadow it. The plugin returns each
Browser target's CDP URL dynamically; no provider server or static instance
URL is configured.

## Working on it

Fix forward. A durable change to the AI stack lands in this repository and
converges by rerunning `scripts/install.sh --install`; never configure the
live machine by hand and call it done. After changing anything here, run:

```sh
tests/validate.sh
```

A new fleet tool usually needs almost no edit here. Name the checkout
`agent*` and export `skills/<name>/SKILL.md`, and the scan ships it into the
fixed private resources. Bare Claude Code and Codex shims do not load them.
The globally installed Codex plugin is skills-only and every name is
persistently disabled until an explicit role enables it;
Codex Desktop and bare invocations therefore receive no fleet
skills unless another explicitly selected role supplies them. AgentVoice can
load the same fixed resource set through a standard role on its own Codex child.
Participant source manifests remain portable and bare; only the Codex
plugin copy qualifies default prompts. Only a tool with its own CLI installer joins the
explicit loop in
`scripts/install-agent-clis`. Its skill name and description provide discovery;
keep the capability and its use cases clear there. Do not add a second catalog
to prompts. The `tool-advertisement-policy` wiki page records the convention.

Plannotator follows that fixed-resource path: AgentStart asks the upstream
installer for only its pinned CLI binary, uses that binary to install the
managed agent-terminal runtime, then carries the same release's `plannotator`,
`plannotator-review`, `plannotator-annotate`, and `plannotator-last` core
skills into Claude Code and Codex. Plan-mode hooks are deliberately not
installed by this integration.

### AgentVoice server defaults

`scripts/agentvoice-config install` links `config/agentvoice/server.json` into
`$XDG_CONFIG_HOME/agentvoice/server.json` (default `~/.config/agentvoice/server.json`).
Full installation runs it after role resource publication. The tracked settings
request full access, disable debug logs, select gpt-5.6-sol at high effort with
the advertised 872,000-token maximum context window, and load the default role.
Missing or empty local placeholders can be linked; nonempty independent
configuration and unrelated links are preserved with an error. AgentVoice loads
settings once per runtime generation. Installation does not restart an active
call or service; new settings apply when AgentVoice next loads its runtime.

AgentStart owns one [default role](roles/README.md) containing prompt Markdown
and a complete MCP inventory. Capability sync renders it at
`~/.local/share/agentstart/resources/roles/default`, expands account paths, and
links shared skills. Its manager owns HUD recording; native workers return
evidence to their parent without another role. The AgentVoice configuration
selects default. Publish the role resource before switching the configured path. Existing
workspace snapshots and active calls retain their loaded contents.

### Account integration credits

[Credits](CREDITS.md) acknowledge the predecessor account tools and link to
AgentUsage's source provenance and upstream license notices.
