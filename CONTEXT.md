# AgentStart context

**The fleet** — the agent apps in `~/code` whose checkouts are named
`agent*` — `agentguidance` carries the general skills — plus `cass` from
`agentchats` and `peekaboo` from `agentdesk`.
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
extension prompts, and every resource in the common capability pack. The AI *desktop
applications* are not toolchain; they are Homebrew casks, and the machine's.
_Avoid_: stack, setup.

**Harness** — an agent CLI a session runs inside: Claude Code, Codex, Pi, Fx.
Skills install into harnesses; AgentLaunch shims balance their bare
launches. _Avoid_: agent (ambiguous with the fleet apps), IDE.

**Extension prompts** — the operator's `SYSTEM.md`, `GUIDELINES.md`, and
`TOOLS.md` under `prompts/agentguidance/`, linked into
`~/.config/agentguidance` and rendered by agentguidance into the
collab/build skills. Their three names are agentguidance's contract; an
unrecognized file renders to nothing. _Avoid_:
config files, dotfiles.

**Advertisement** — a tool's one line in `TOOLS.md` saying when to load its
skill. A line is attention spent in every session and has to earn it; the
policy and its standing decisions live in the wiki
(`agentwiki get tool-advertisement-policy`). _Avoid_: documentation,
listing (an installed, unadvertised tool is still fully documented by its
skill).

**The sync path** — `scripts/sync-skills`: the unattended-safe convergence
the scheduled updater runs every six hours — the participant scan into the
default `common` capability pack, projection refresh, no elevation, no
compatibility-root cleanup, no restarts. _Avoid_: update, upgrade (binaries
never move on this path).

**Capability pack** — an AgentStart-installed bundle of session-visible
resources: portable skills and guidance plus explicitly harness-specific
commands, extensions, templates, and configuration. Packs live only under
`~/.local/share/agentstart/capabilities/packs`; AgentLaunch composes them for a
session. _Avoid_: skill pack (a pack contains more than skills), plugin (that
is only one harness projection).

**The common pack** — the default capability pack, named `common`, containing
every fleet participant skill, external managed skill, the canonical global
`AGENTS.md`, and AgentStart's session resources. Every managed launch includes
it unless explicitly suppressed. _Avoid_: core plugin, agentstart-core.

**Subagent capability** — the fleet's answer to a harness that dispatches no
workers of its own. Pi's is the pinned `pi-subagents` package, installed
self-contained and carried in the common pack's `pi_extensions` resource,
which registers a dispatch tool, its skills, and its workflow prompt
templates from one directory. _Avoid_: subagent plugin (Pi calls the unit a
package), worker (that is what a dispatched agent is, not the capability).

**Session projection** — an immutable harness-native rendering of one resolved
set of capability packs. Claude receives one plugin named `agent`, Codex
receives standalone extra skill roots, and Pi receives explicit skill,
extension, and template paths. _Avoid_: install (a projection is selected for
one launch, not registered globally).

**Compatibility projection** — the temporary Codex plugin named `agent` for
desktop and other Codex clients that do not launch through AgentLaunch. It is
rendered from `common`; portable manifests stay bare in the pack and only the
plugin copy qualifies names as `$agent:<name>`. AgentLaunch enumerates this
projection and name-disables those qualified aliases in managed sessions,
because Codex does not apply session-flag plugin enablement to plugin loading.
_Avoid_: canonical plugin.

**The Herdr config render** — the live `~/.config/herdr/config.toml` rendered
by AgentStart from its tracked behavior config, which carries no palette.
`herdr-config` validates and replaces the live file, so neither checkout
becomes program-written state; it is rendered rather than linked because Herdr
writes its own keys into it.
_Avoid_: dotfile, theme config (the render sets no colors at all).

**Participant** — an `agent*` checkout that exports
`skills/<name>/SKILL.md` and is therefore discovered by the scan. A
checkout without one is not misconfigured; it is simply not a participant.
This repository is itself a participant (the `fleet` skill). _Avoid_:
registered, enrolled (there is no registry — the convention is the whole
interface).

**Supervisor** — a persistent agent role that watches peer lifecycle events,
obtains readiness for an exact commit, integrates that commit into local
`main`, pushes `origin/main`, and reaps a clean worktree only after Herdr has
observed its agent end and workspace close. It preserves the branch and a
durable association receipt. _Avoid_: orchestrator (a broader control-plane
role), Land (which combines integration and release).
