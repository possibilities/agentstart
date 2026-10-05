# AgentStart glossary

Names for the fleet capabilities and ownership boundaries this repository coordinates.

**The fleet** — the agent apps in `~/code` whose checkouts are named
`agent*` — `agentguidance` carries the general skills — plus `chats` from
`agentchats`; `agentdesk` supplies the Computer Use desktop skill.
Each fleet repo owns its own hardened installer and exports its own skills;
AgentStart invokes contracts and never reaches inside a sibling checkout.
_Avoid_: suite, monorepo, workspace.

**Workshop** — a first-party repository under `~/workshops` that owns the
maintenance specification and delivery contract for a downstream fork. Its
bound fork checkout lives inside the Workshop at ignored `fork/`, or
`fork/<repo>` when it owns multiple forks. Persistent maintenance worktrees
live at ignored `worktrees/`; `~/source` holds upstream reference clones.
AgentStart consumes the `codexnk` and `fxnk` installer contracts from this
root, independently of the fleet's `~/code` root.
_Avoid_: clone, fork checkout, fleet repo.

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

**Harness** — an agent CLI a session runs inside: Claude Code, Codex, Fx, Pi,
OpenCode 2 (`opencode`), or Devin CLI.
Bare Claude Code and Codex use AgentStart's permission-only shims;
Codex and Fx shims bind the exact workshop-owned installations; Fx passes
arguments unchanged. Pi is installed as a bare CLI outside that launch path.
OpenCode 2 is installed in a private prefix and exposed as `opencode`.
The former V1 executable is retired after V2 verification; already running
V1 sessions are not terminated.
_Avoid_: agent (ambiguous with the fleet apps), IDE.

**Devin terminal invocation** — AgentStart's owned `~/.local/bin/devin` wrapper around the official versioned binary. Terminal sessions run in the original checkout with a temporary `.devin` snapshot of the current default Role's skills and MCPs; `/prime` loads its append prompt only when manually called. Many sessions may share a Git root and its snapshot, and the snapshot merges alongside an existing project `.devin` without overwriting it. A periodic AgentStart cleanup service removes the marked snapshot once every wrapper and native child process identity for the root has ended. Utility and ACP commands pass directly to the native CLI. The native login and session database remain Devin-owned. _Avoid_: global Devin plugin, per-session worktree, second credential store.

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
omits Chats, and its skill set excludes the Chats skill. Archived owners' MCPs
and skills are removed from the common inventory as well;
the inventory has no AgentStart-owned HTTP projection. There are no selectable
packs. _Avoid_: capability pack, common pack, projection.

**Archived fleet checkouts** — preserved source and data under `~/archive`,
not active CLI, MCP, skill, or service participants. AgentStart retires only
its exact owned links and LaunchAgents for the named former owners; existing
session snapshots are not rewritten. Legacy AgentBoard CLI and data remain
available for archival queries without Board/Groom skills or an active MCP.
_Avoid_: compatibility redirect, dual installation, deleting private state.

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
separate role directory. The inventory omits Chats and excludes its skill;
archived owners are absent from the common inventory. Generic
native worker report-and-review accountability remains. Role exposure does not
authenticate or revoke native tools. _Avoid_: manager role,
worker role, AgentVoice-owned prompt.
