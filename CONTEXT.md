# AgentStart context

**The fleet** — the agent apps in `~/code` whose checkouts are named
`agent*` — `agentguidance` carries the general skills — plus `chats` from
`agentchats`; `agentdesk` supplies the Computer Use desktop skill.
Each fleet repo owns its own hardened installer and exports its own skills;
AgentStart invokes contracts and never reaches inside a sibling checkout.
_Avoid_: suite, monorepo, workspace.

**The boundary rubric** — the one-sentence ownership test for this
repository: depended on by or deeply related to the fleet → AgentStart; the
machine itself (Homebrew, Stow, launchd, macOS settings, account migration)
→ the machine layer, which this repository does not own and does not name.
_Avoid_: split, refactor, migration (those name the event; the rubric names
the rule).

**The toolchain** — everything `scripts/install.sh --install` converges:
harness CLIs, pinned npm globals, MCP registration, guidance links,
extension prompts, and every fixed private fleet resource. Individual stdio
MCPs share one installed inventory for explicit roles and AgentVoice. AgentStart
does not translate that inventory into an HTTP gateway or publish it through
Tailscale. General-purpose AI desktop clients belong to the machine layer. Gog
owns its Google credential store.
_Avoid_: stack, setup.

**Smolmux source installation** — Smolmux's repository-owned `scripts/install.sh`,
which AgentStart invokes through the same contract as other source consumers.
Smolmux owns the editable command, exact source-built Companion pin and doctor
verification; its arbitrary-command sessions require no Fx pin or agent MCP.
_Avoid_: release path, bucket installer, AgentStart-owned Smolmux installer.

**Fx Integration consumer pin** — The exact published Fx commit AgentStart
passes to fxnk's installer after that commit has passed fxnk's Local
development gate and ship gate. Ordinary convergence reuses the pin; only an
Fx maintenance cycle advances it, so a moving remote branch is never treated
as approval.
_Avoid_: latest Fx, Fx version, integration tip.

**Harness** — an agent CLI a session runs inside: Claude Code, Codex, Fx, Pi, OpenCode, Devin CLI.
Bare Claude Code and Codex use AgentStart's permission-only shims;
Codex and Fx shims bind the exact workshop-owned installations; Fx passes
arguments unchanged. Pi is installed as a bare CLI outside that launch path.
_Avoid_: agent (ambiguous with the fleet apps), IDE.

**Devin worktree invocation** — AgentStart's owned `~/.local/bin/devin` wrapper around the official versioned binary. Terminal sessions start in a new Git worktree with a private `.devin` copy of the current default Role's skills and MCPs; `/prime` loads its append prompt only when manually called. Utility and ACP commands pass directly to the native CLI, and resume requires an existing AgentStart-owned worktree. The native login and session database remain Devin-owned. _Avoid_: global Devin plugin, in-place project setup, second credential store.

**Codex invocation profile** — A private, uniquely named native profile copied
from Funk's authored preferences for one Codex runtime process. AgentStart's
optional `codex-invocation` helper adds trust for the effective cwd and project root, retains the existing
Codex home, and removes the profile when the child exits.
_Avoid_: temporary Codex home, config sync, trust database.

**Extension prompts** — the operator's `SYSTEM.md` and `GUIDELINES.md` under
`prompts/agentguidance/`, linked into `~/.config/agentguidance` and rendered
by agentguidance into the collab/build skills. Those two names are
agentguidance's contract; an unrecognized file renders to nothing. _Avoid_:
config files, dotfiles.

**The sync path** — `scripts/sync-skills`: the unattended-safe convergence
the scheduled updater runs every six hours — the participant scan into the
fixed private resources, harness render refresh, no elevation, binary updates,
or service restarts. _Avoid_: update, upgrade (binaries never move on this
path).

**Fleet resources** — the one fixed private set under
`~/.local/share/agentstart/resources`: every fleet and external managed skill,
canonical guidance, the fleet-owned shadcn registry MCP, the session-only Claude
plugin, and the globally installed but inert Codex skills-only plugin. Bare
shims supply no skills or MCP inventory; the
explicit `default` role supplies its own MCP and skill layer. Its MCP roster
omits Attention, Chats, Grok, HUD, Keys, Mux, Sounds, and Surface, and its skill
set excludes those owners' dedicated skills and their workflows;
the inventory has no AgentStart-owned HTTP projection. There are no selectable
packs. _Avoid_: capability pack, common pack, projection.

**AgentHUD** — the independent `~/code/agenthud` project, `agenthud` command,
and `hud` skill: the durable Work owner and read-only HUD projection for managed
sessions. Its installer prepares only the command, dependencies, and web assets;
AgentStart owns the resident `io.arthack.agenthud.serve` LaunchAgent that runs
the editable default view at `https://agenthud.localhost`. Legacy AgentBoard data,
CLI, and stdio MCP implementation remain available for archival queries, while
Board/Groom skills and the AgentBoard MCP are absent from active fleet
resources. AgentBoard has no socket service endpoint.
_Avoid_: Board redirect, dual write, AgentVoice-owned AgentHUD.

**Archived AgentLab** — the retired AgentLab (Greybird) project preserved as
reference source and history, outside the active fleet. AgentStart keeps no
command-install, build, Portless, Codex-daemon, or Fx-broker edge to it. A
bounded retirement path removes only the three exact former AgentStart-owned
LaunchAgents; source, durable records, databases, and state remain preserved.
_Avoid_: dormant service, compatibility route, redirected command, data
migration.

**AgentVoice transcript reader** — AgentVoice's foreground `agentvoice serve`
command and transcript UI at `https://agentvoice.localhost`. Bare direct
invocations stay editable for development; AgentStart's resident
`io.arthack.agentvoice.serve` LaunchAgent uses the installer-prepared production
build. The reader observes the separately owned AgentVoice waiting server but
has no call, menu, client, or server lifecycle authority. _Avoid_: AgentVoice
server service, reader-owned call, Native SDK shell service.

**AgentVoice isolated test services** — The bounded interim pair supervised by
AgentStart as `io.arthack.agentvoice-test.wait` and `.serve`. Both execute the
dedicated `~/worktrees/agentvoice/parallel-test-environment/agentvoice` checkout
against `~/.local/state/agentvoice/test-workspace`; only the reader claims
`https://agentvoice-test.localhost`. They are one replaceable deployment unit,
not a named-session model. _Avoid_: second production server, session registry,
default endpoint, permanent multi-session service.

**Codex fleet plugin** — the globally installed, strictly skills-only plugin
`agent@agentstart-managed`. AgentStart persistently name-disables every
`agent:<skill>` by default; explicit roles may enable their own resources.
The bare shim does not enable fleet skills or MCPs. _Avoid_: compatibility projection, extra
root.

**The Herdr config render** — the live `~/.config/herdr/config.toml` rendered
by AgentStart from its tracked behavior config, which carries no palette.
`herdr-config` validates and replaces the live file, so neither checkout
becomes program-written state; it is rendered rather than linked because Herdr
writes its own keys into it.
_Avoid_: dotfile, theme config (the render sets no colors at all).

**The Herdr Codex session fallback** — a temporary AgentStart-owned
`SessionStart` hook installed at Herdr integration v8's existing trusted
command path. It reports a new Codex thread through Herdr's public CLI only
when `HERDR_ENV=1`, and becomes a no-op when
the installed Herdr integration version advances past 8. Its dedicated source,
installer, and test are one deletion unit for Herdr retirement.
_Avoid_: Herdr patch, plugin hook (neither is used).

**Participant** — an `agent*` checkout that exports
`skills/<name>/SKILL.md` and is therefore discovered by the scan. A
checkout without one is not misconfigured; it is simply not a participant.
This repository is itself a participant (the `fleet` skill). _Avoid_:
registered, enrolled (there is no registry — the convention is the whole
interface).

**Launch service label** — An account-owned launchd identifier shaped as
`io.arthack.<project>.<verb>`. It names the project and the action performed;
an exact installer marker separately proves which repository may replace or
retire it. _Avoid_: noun-role label, ownership namespace.

**Model invocation policy** — the portable fact recorded by
`disable-model-invocation` in a skill's `SKILL.md` frontmatter; absent or false
means model-invocable. The fixed-resource render derives Codex's inverse
`allow_implicit_invocation` field from it, while Claude consumes the fact
directly. _Avoid_: OpenAI policy (that is one rendered representation).

**Working role** — The AgentStart-owned `default` directory of prompt Markdown
and its complete MCP inventory. Its manager owns human dialogue and overall
delivery; native workers own assignments and report to their parent without a
separate role directory. The inventory omits Attention, Chats, Grok, HUD, Keys,
Mux, Sounds, and Surface MCPs and excludes their dedicated skills (`attention`,
`bus`, `chats`, `grokbot`, `hud`, `keys`, `sounds`) and their workflows; generic
native worker report-and-review accountability remains. Role exposure does not
authenticate or revoke native tools. _Avoid_: manager role,
worker role, AgentVoice-owned prompt.
