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
    the fixed private resources and linked from there into the Claude Code and
    Codex global slots. Advice belongs in the extension prompts.
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

  - Claude Code and Codex, by their official installers, plus the official
    Homebrew cask for the standalone Grok Build CLI/TUI (without AgentLaunch
    or Herdr integration yet);
  - Gog through its Homebrew formula, with separate MCP registrations for the
    two declared Gmail accounts and Google-owned sign-in;
  - the pinned FastMCP HTTP transport, private toolset configuration and
    credentials, and an authenticated Tailscale route;
  - Zig (an intentional duplicate of the machine's Brewfile), `llm`, the
    pinned Plannotator review CLI with its managed agent-terminal runtime and
    version-matched core skills, and the Homebrew-installed Hunk review TUI
    with its version-matched bundled skill;
  - smolmux's repository-owned source installer and pinned Companion, plus the
    generated live Herdr config and linked smolmux key config;
  - the pinned `@native-sdk/cli` and `agent-browser` npm globals, plus the
    linked ordered agentbrowse deployment and provider configs backed by
    `agentbrowse provider`;
  - individual fleet MCPs, Agentdesk, termctrl, agent-browser, account-bound Gog,
    and the fleet-owned shadcn registry through one shared resource inventory;
  - the `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` guidance links, and
    the extension prompt links;
  - the external skills and fixed private fleet resources;
  - the agentwiki, agentboard, agentbrowse-infra, agentbrowse, agentattention,
    agentsearch, agentkeys, grok-swap, agentusage, agentlaunch, and agentgrok
    CLIs;
  - AgentUsage’s owned Claude/Codex accounts and single proxy through its
    existing observer daemon; enroll/import accounts before switching balanced
    consumers, then converge the service after AgentUsage and AgentLaunch.
    No Claude/Codex swap checkout or command is an installation prerequisite;
    existing checkouts, backups and credentials are preserved;
  - agentchats, the fleet launch agents, and finally `sync-skills`.

  The machine's installer calls this and refuses to finish without it.
  `--check` prints the plan without changing anything.
- `scripts/sync-skills` — the cheap convergence path: the agent* checkout
  scan into `~/.local/share/agentstart/resources`, followed by harness render
  refresh. The scheduled updater calls this every six hours. It
  never removes a skill from a compatibility root or restarts services.
  `--check` prints the plan.
- [`docs/agent-interfaces.md`](docs/agent-interfaces.md) — the policy and
  support matrix for MCP, native harness, and CLI/TUI workflows. A workflow
  needs one authoritative surface; an MCP wrapper is not required when the
  harness or interactive tool already owns the contract.
- `scripts/install-agentlaunch-shims` — the balanced-launch shims for bare
  `claude`/`codex`; the machine's wrapper of the same name delegates
  here. The full installer also converges them. Codex runtime calls receive
  [invocation profiles](config/codex/README.md) copied from Funk's personal
  defaults, with temporary cwd/project trust and the normal Codex home intact.
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
the private shared resources. AgentLaunch loads it for Claude and Codex;
AgentVoice's prepared default role links the same file. Discovery happens in
the MCP host, without a repository scan at launch. Shadcn retains project cwd.

The [HTTP gateway](gateway/README.md) exposes configured toolsets at
/mcp/<toolset>. Each set has a separate bearer credential and a server-enforced
tool selection. It preserves stdio session state and native MCP results.
Grok Build remains outside AgentLaunch and Herdr.

For a full install while a voice call is active, set
AGENTSTART_PRESERVE_AGENTVOICE_SERVICE=1. This uses AgentVoice's supported
--command-only installer mode; the prepared role applies to subsequent calls.

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
panel (left, left drawer, dock, right) saying which program runs there and whether
it starts shown. agentmux reads it at start and never
writes it. agentmux and agentwork install in the fleet CLI loop; agentwork
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
fixed private resources. AgentLaunch loads those resources into every managed
session: Claude Code exposes `/agent:<name>` and Codex `$agent:<name>`. The
globally installed Codex plugin is skills-only and every name is
persistently disabled until AgentLaunch enables it in a session;
Codex Desktop and deliberate real-binary bypasses therefore receive no fleet
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
Full installation runs it before the fleet CLI installers. The tracked settings
request full access, debug logs, gpt-6-astra at low effort and the default AgentVoice
role. Missing or empty local placeholders can be linked; nonempty independent
configuration and unrelated links are preserved with an error. AgentVoice loads
settings once per runtime generation. Installation does not restart an active
call or service; new settings apply when AgentVoice next loads its runtime.

The fixed-resource renderer prepares
`~/.local/share/agentstart/resources/agentvoice/default` as a standard role.
The tracked server configuration selects this prepared role.
Its prompt files link to the app-owned `~/code/agentvoice/roles/default`, and
its `skills` and `mcp.json` link to the already synchronized portable skills
and MCP resources. The role therefore keeps AgentVoice's default instructions
and native delegation while supplying the same fleet workflows. Its skills
use their bare names (`$board`, for example); the source invocation policy
still controls implicit use. Each MCP is configured directly for the thread.
Shadcn runs from the fixed fleet registry directory, independent of the
conversation workspace, and is also available through authenticated HTTP
toolsets.

Publish these role resources before selecting their path in the operator's
server config. The native role mechanism registers skill roots only with the
owned child and adds MCP config to its thread; this does not enable a global
plugin or rewrite prompt files. The renderer preserves independent roles and
refuses modified generated files or app-owned skill/MCP definitions that
would require an explicit composition decision. The public role format stays
the AgentRoles/AgentVoice contract, with no extra runtime layer.

### Account integration credits

[Credits](CREDITS.md) acknowledge the predecessor account tools and link to
AgentUsage's source provenance and upstream license notices.
