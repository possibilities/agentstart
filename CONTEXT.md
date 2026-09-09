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
extension prompts, every fixed private fleet resource, and the authenticated
HTTP gateway. Individual stdio MCPs share one installed inventory across
AgentLaunch and AgentVoice; external clients receive configurable toolsets at
/mcp/<toolset>, each with separate authentication. General-purpose AI desktop
clients belong to the machine layer. Gog owns its Google credential store.
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

**Harness** — an agent CLI a session runs inside: Claude Code, Codex, Fx.
AgentLaunch balances Claude Code and Codex and loads their fleet resources;
Fx has its own workshop-owned installation and is outside that launch path. _Avoid_: agent (ambiguous with the fleet apps), IDE.

**Codex invocation profile** — A private, uniquely named native profile copied
from Funk's authored preferences for one Codex runtime process. AgentStart's
shim adds trust for the effective cwd and project root, retains the existing
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
plugin, and the globally installed but inert Codex skills-only plugin. Every
managed AgentLaunch and AgentVoice session receives the skills and MCP inventory;
authenticated HTTP toolsets can include the same shadcn service. There are no
selectable packs. _Avoid_: capability pack, common pack, projection.

**Codex fleet plugin** — the globally installed, strictly skills-only plugin
`agent@agentstart-managed`. AgentStart persistently name-disables every
`agent:<skill>`; AgentLaunch name-enables the fixed set in its session layer,
exposing `$agent:<name>` without leaking fleet skills into
unmanaged Codex or Fx-visible roots. _Avoid_: compatibility projection, extra
root.

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

**Launch service label** — An account-owned launchd identifier shaped as
`io.arthack.<project>.<verb>`. It names the project and the action performed;
an exact installer marker separately proves which repository may replace or
retire it. _Avoid_: noun-role label, ownership namespace.

**Model invocation policy** — the portable fact recorded by
`disable-model-invocation` in a skill's `SKILL.md` frontmatter; absent or false
means model-invocable. The fixed-resource render derives Codex's inverse
`allow_implicit_invocation` field from it, while Claude consumes the fact
directly. _Avoid_: OpenAI policy (that is one rendered representation).
