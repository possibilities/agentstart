#!/bin/bash

set -euo pipefail

check_only=0
content_only=0
script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd)
repo_root=$(cd -P -- "$script_dir/.." && pwd)

# The fleet root. AGENTSTART_CODE_ROOT relocates it as a unit — the tests point
# it at a fixture tree — but it deliberately does not resolve relative to this
# script: the installer converges the machine, not the checkout it was invoked
# from, and a worktree run must still find the real fleet rather than silently
# skipping every tool.
code_root="${AGENTSTART_CODE_ROOT:-$HOME/code}"
# Fx maintenance advances this only after fxnk's exact-SHA local gate and ship
# gate approve the published Integration commit. Ordinary convergence reuses
# that reviewed consumer pin; it never treats the current remote tip as an
# implicit approval.
fx_integration_sha=e6ef2148c63f304883de21768bcfcdbf97c4d833
# Plannotator's core skills describe its CLI surface, so the two pins move as
# one. The upstream installer runs in binary-only mode below; AgentStart owns
# skill delivery through the fixed private resources instead of allowing the
# vendor installer to populate ambient harness roots.
plannotator_version=0.27.9
resources_root="${AGENTSTART_RESOURCES_ROOT:-$HOME/.local/share/agentstart/resources}"
resources_skills_state_root="$resources_root/skills-state"

usage() {
    cat <<'EOF'
Usage: scripts/install.sh [--install|--check|--content]

Install the AI tools, harness configuration, and agent skills owned by
AgentStart. The machine's installer invokes this after converging the machine
layer; it is also safe to run standalone.

Options:
  --install  Install or upgrade everything
  --check    Print the installation plan without changing the system
  --content  Converge only what this repository owns as content — skills,
             prompts, guidance, the statusline, and fixed fleet resources —
             installing and upgrading nothing. Cheap and safe to rerun on a
             machine a full install has already converged.
EOF
}

die() {
    printf 'AgentStart installer: %s\n' "$*" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$script_dir/agent-browser-link.sh"

find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

install_official() {
    local name="$1"
    local url="$2"
    local interpreter="$3"
    local installer_file
    shift 3

    printf 'Installing %s with its official installer.\n' "$name"
    # Download the response completely before starting the vendor installer.
    # Some installers deliberately stop reading stdin early; piping curl into
    # them turns that success into curl error 56 under pipefail.
    (
        installer_file=$(mktemp "${TMPDIR:-/tmp}/agentstart-official-installer.XXXXXX") \
            || die "creating a temporary file for the $name installer failed"
        trap 'rm -f -- "$installer_file"' EXIT
        [ -f "$installer_file" ] \
            || die "temporary file for the $name installer is unavailable: $installer_file"
        /usr/bin/curl -fsSL "$url" -o "$installer_file"
        "$interpreter" "$@" <"$installer_file"
    )
}

install_private_skill_pack() {
    local source="$1"
    shift

    mkdir -p "$resources_root" "$resources_skills_state_root"
    CLAUDE_CONFIG_DIR="$resources_root" XDG_STATE_HOME="$resources_skills_state_root" \
        "$script_dir/run-skills-cli" npx --yes skills add "$source" \
        --agent claude-code \
        --skill "$@" \
        --global --copy --yes \
        || die "installing agent skills failed: $source ($*)"
}

# AgentStart owns one guidance slot for each managed harness. Link both to the
# fixed resource set's canonical AGENTS.md, which stays deliberately empty — global
# advice belongs
# in the extension prompts below, rendered into the collab and build skills,
# not in a file loaded into every session. Claude Code reads only CLAUDE.md,
# while Codex skips empty guidance files. An independent non-symlink file with
# content at either target is preserved and reported — the same conflict rule
# the guidance file itself prescribes for repositories.
link_agent_guidance() {
    local source="$resources_root/guidance/AGENTS.md"
    local target

    [ -f "$source" ] \
        || die "agent guidance source is missing: $source"

    for target in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
        if [ ! -L "$target" ] && [ -s "$target" ]; then
            die "refusing to replace independent guidance: $target"
        fi
        mkdir -p "$(dirname "$target")"
        ln -sfn "$source" "$target"
        cmp -s "$source" "$target" \
            || die "linked guidance does not resolve to $source: $target"
    done
}

# The operator extension prompts are cross-project guidance, so AgentStart
# owns them: prompts/agentguidance/ here is the source of truth, and
# ~/.config/agentguidance is links into this checkout. Agentguidance's
# renderer reads that directory when composing the guided skills,
# so these links must exist before its post-sync hook fires in sync-skills.
# The recognized names — SYSTEM.md and GUIDELINES.md — are
# agentguidance's contract; an unrecognized file renders to nothing. An
# independent non-symlink file with content is preserved and reported, the
# same conflict rule as the guidance links above.
link_extension_prompts() {
    local config_dir="$HOME/.config/agentguidance"
    local name
    local source
    local target

    for name in SYSTEM.md GUIDELINES.md; do
        source="$repo_root/prompts/agentguidance/$name"
        target="$config_dir/$name"
        [ -f "$source" ] \
            || die "extension prompt source is missing: $source"
        [ -s "$source" ] \
            || die "extension prompt source is empty: $source"
        if [ ! -L "$target" ] && [ -s "$target" ]; then
            die "refusing to replace independent extension prompt: $target"
        fi
        mkdir -p "$config_dir"
        ln -sfn "$source" "$target"
        cmp -s "$source" "$target" \
            || die "linked extension prompt does not resolve to $source: $target"
    done
}

# Everything this repository owns as content, in the one order that works.
#
# The full install runs this as its last act, and `--content` runs it alone.
# That is the whole difference between the two: a full install converges the
# machine — Homebrew formulas, the harness CLIs, built binaries, services —
# and then converges content on top of it, while `--content` trusts that the
# machine is already there and rebuilds only what a `git pull` in this
# checkout can change.
#
# It is not a second installer and not a second synchronization path. Every
# step below is a step the full install already ran, called from one place so
# the two can never disagree about what content convergence means.
#
# What it deliberately leaves out is anything that installs, upgrades, or
# downloads, including the pinned third-party skill packs. Those persist from
# the last full install, and the renderer below carries whatever they left
# behind. A machine that has never had a full install is not a machine this
# mode can converge.
converge_repo_content() {
    printf 'Linking the operator extension prompts into ~/.config/agentguidance.\n'
    link_extension_prompts

    # The fleet statusline is harness configuration in each CLI's own idiom, so
    # it converges here rather than from a launcher. It reads config the harness
    # installers create, which is why content convergence assumes a machine a
    # full install has already been through.
    "$script_dir/install-statusline" --install

    # Every agent tool publishes its skills by convention — skills/<name>/
    # inside a checkout named agent* — so they are discovered rather than
    # listed here, and a tool that adds or renames a skill needs no edit in
    # this file. That includes this checkout's own skills and agentguidance's,
    # whose post-sync hook re-renders the templates the scan ships against the
    # operator extension prompts linked above.
    "$script_dir/sync-skills"

    # The sync above renders the canonical guidance source. Link
    # the two harness discovery slots only after that source is guaranteed
    # to exist.
    printf 'Linking the fleet harness guidance for Claude Code and Codex.\n'
    link_agent_guidance

}

case "${1:-}" in
    --install)
        ;;
    --check)
        check_only=1
        ;;
    --content)
        content_only=1
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac
[ "$#" -eq 1 ] || {
    usage >&2
    exit 64
}

# Content convergence is the tail of a full install run on its own. It refuses
# to guess at a machine it has never seen: without the fixed resources there has
# been no full install, and rendering content into a machine whose harnesses
# and binaries are absent would report success over a half-built system.
if [ "$content_only" -eq 1 ]; then
    [ "$(uname -s)" = Darwin ] || die "macOS is required"
    [ "$(id -u)" -ne 0 ] || die "run as the target user, not root"
    command -v npx >/dev/null 2>&1 || die "npx is required to install agent skills"
    [ -d "$resources_root" ] \
        || die "no fixed fleet resources at $resources_root; run scripts/install.sh --install first"
    printf 'Converging AgentStart repository content only; installing nothing.\n'
    converge_repo_content
    printf 'AgentStart content convergence complete.\n'
    exit 0
fi

if [ "$check_only" -eq 1 ]; then
    cat <<'EOF'
Homebrew casks:
  brew install or upgrade --cask grok-build  # official Grok Build CLI/TUI; no AgentLaunch or Herdr integration

Command-line tools:
  curl -fsSL https://claude.ai/install.sh | XDG_CACHE_HOME=~/Library/Caches bash  # keep vendor staging off a machine-managed ~/.cache symlink
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
  scripts/install-agentlaunch-shims  # Codex native profiles and Stowed Claude preferences with cwd/worktree trust
  agentstart config apply  # Validate generated preference snapshots; watcher reports native drift without writing Funk
  curl -fsSL https://plannotator.ai/install.sh | bash -s -- --version v0.27.9 --minimal --non-interactive  # binary only; AgentStart carries the skills
  ~/.local/bin/plannotator install-runtime agent-terminal  # managed WebTUI/PTY runtime omitted by the minimal installer
  brew install or upgrade zig  # Native SDK packaging requires it
  ~/code/fxnk/scripts/install.sh --install --sha e6ef2148c63f304883de21768bcfcdbf97c4d833  # exact ship-gate-approved Fx Integration consumer pin
  brew install or upgrade llm  # an AI CLI, so AgentStart's outright — moved out of the machine's Brewfile
  brew install or upgrade hunk  # review-first diff TUI whose bundled agent skill follows the installed build
  brew install or upgrade rustup  # Terminal Control builds from crates.io with the current stable Rust toolchain
  brew install or upgrade zig@0.15  # Terminal Control's libghostty-vt build requires the keg-only 0.15 line
  "$(brew --prefix rustup)/bin/rustup" toolchain install stable --profile minimal
  PATH="$(brew --prefix)/opt/zig@0.15/bin:$PATH" "$(brew --prefix rustup)/bin/rustup" run stable cargo install --locked --root "$HOME/.local" terminal-control
  install AgentStart's detached-start shim at ~/.local/bin/termctrl while retaining the upstream executable under ~/.local/libexec/agentstart/terminal-control
  brew install herdr when absent and every default/named server socket is proved inactive; upgrade only with AGENTSTART_HERDR_ALLOW_UPGRADE=1 and the same socket gate
  herdr integration install claude and codex into their canonical homes
  scripts/install-herdr-codex-session-fallback --install  # temporary v8 bridge; active only inside AgentLaunch+Herdr and self-disables after the integration advances
  herdr plugin link ~/code/agentsurface/plugin  # the fleet popup panes + tab-naming plugin; a link registers the checkout path, so relinking is a safe converge
  ~/code/smolmux/scripts/install.sh --install  # canonical consumer path: editable smolmux plus its exact source-built smolmux-zmx Companion pin
  scripts/smolmux-config install  # link the Herdr-compatible smolmux key subset with the operator's Ctrl-Space prefix
  scripts/agentvoice-config install  # link the operator's AgentVoice server settings
  scripts/agentmux-config install  # link the operator's default agentmux instance config (setup, parts, prefix, harnesses)
  scripts/herdr-config install  # render, validate, and activate the generated Herdr config, then reload it
  npm install --global @native-sdk/cli@0.7  # the line the native-sdk skill documents
  npm install --global agent-browser@0.33.2  # Agentbrowse provider + Agentscrape stable-session driver share this exact build
  ln -sfn "$(realpath "$(npm prefix --global)/bin/agent-browser")" ~/.local/bin/agent-browser  # the candidate Agentscrape resolves before PATH
  scripts/agentbrowse-config install  # link the locked Artbird-first, already-enabled-Apple-second deployment configuration
  scripts/agent-browser-config install  # select agentbrowse's short-lived ordered provider; no provider server or static URL
  ~/code/agentvoice/scripts/install.sh --install  # via install-agent-clis: editable command + native audio build + waiting default LaunchAgent; no voice call
  ~/code/agentnotify/scripts/install.sh --install  # native menu bar inbox + parity CLI; preserve the current running release
  install ~/.local/bin/terminal-notifier router  # prefer AgentNotify; keep the real notifier as an availability fallback
  bun scripts/agentvoice-network.ts --install  # converge an explicitly enabled dedicated tailnet-only route; never grant credentials or enable Funnel
Agent documentation:
  native skills list

Agent guidance:
  ln -sfn ~/.local/share/agentstart/resources/guidance/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md
  ln -sfn ~/.local/share/agentstart/resources/guidance/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files
  ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against

Fixed private fleet resources:
  install external skill packs with --copy into ~/.local/share/agentstart/resources/skills
  scripts/install-gog --install  # direct Google MCP access; existing account credentials stay in gogcli
  scripts/install-mcp-gateway --install  # private toolsets and per-toolset credentials; pinned FastMCP transport
  scripts/install-mcp-gateway --expose  # authenticated /mcp/<toolset> through Tailscale, preserving unrelated routes
  render the individual fleet MCPs, termctrl, agent-browser, gog, and fleet shadcn registry service for managed sessions and HTTP toolsets
  https://github.com/vercel-labs/skills: find-skills
  https://github.com/vercel-labs/agent-skills: web-design-guidelines, vercel-react-best-practices
  https://github.com/vercel/ai: ai-sdk
  https://github.com/vercel/ai-elements: ai-elements
  https://github.com/shadcn/ui: shadcn
  https://github.com/vercel-labs/native: native-sdk
  https://github.com/backnotprop/plannotator/tree/v0.27.9/apps/skills/core: plannotator, plannotator-review, plannotator-annotate, plannotator-last
  anomalyco/terminal-control@v<installed termctrl version>: terminal-control
  hunk skill path hunk-review  # the review skill ships inside the binary and stays version-matched to it
  install hunk-review with --copy into the fixed resources
  herdr --skill, rendered to ~/.local/share/agentstart/herdr-skill/skills/herdr/SKILL.md  # the surface skill ships inside the binary, so it converges with the installed build, never a stale copy
  install herdr with --copy into the fixed resources

Content convergence (everything below is also scripts/install.sh --content,
which runs it alone and installs nothing):
EOF
    "$script_dir/install-statusline" --check
    "$script_dir/install-launchagents" --check
    printf '  scripts/configure-agentsource-webhooks --check  # silent when Funnel, inspectable GitHub hook state, reconciliation provenance, and the live receiver agree; otherwise an agent-ready handoff\n'
    "$script_dir/sync-skills" --check
    if [ -f "$code_root/agentchats/scripts/install.sh" ]; then
        "$code_root/agentchats/scripts/install.sh" --check
    fi
    if [ -f "$code_root/agentdesk/scripts/install.sh" ]; then
        "$code_root/agentdesk/scripts/install.sh" --check
    fi
    exit 0
fi

[ "$(uname -s)" = Darwin ] || die "macOS is required"
[ "$(id -u)" -ne 0 ] || die "run as the target user, not root"

brew_bin=$(find_brew) || die "Homebrew is not installed"
brew_prefix=$("$brew_bin" --prefix)
brew_owner=$(stat -f '%Su' "$brew_prefix")
[ "$brew_owner" = "$(id -un)" ] \
    || die "Homebrew prefix $brew_prefix is owned by $brew_owner, not $(id -un)"

# The machine already owns these PATH entries in its Stow-managed zsh config.
# Supplying them here prevents vendor installers from appending equivalent lines
# to shell startup files during this run.
original_path=$PATH
export PATH="$HOME/.local/bin:$brew_prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin:$original_path"

install_or_upgrade_formula() {
    local formula="$1"

    if "$brew_bin" list --formula --versions "$formula" >/dev/null 2>&1; then
        "$brew_bin" upgrade --formula --yes "$formula"
    else
        "$brew_bin" install --formula --yes "$formula"
    fi
    "$brew_bin" list --formula --versions "$formula" >/dev/null \
        || die "Homebrew formula verification failed: $formula"
}

install_or_upgrade_cask() {
    local cask="$1"

    if "$brew_bin" list --cask --versions "$cask" >/dev/null 2>&1; then
        # --greedy keeps casks that declare their own update behavior under
        # AgentStart's Homebrew convergence instead of deferring to the app.
        "$brew_bin" upgrade --cask --greedy --yes "$cask"
    else
        "$brew_bin" install --cask --yes "$cask"
    fi
    "$brew_bin" list --cask --versions "$cask" >/dev/null \
        || die "Homebrew cask verification failed: $cask"
}

export HOMEBREW_NO_ASK=1

"$script_dir/install-gog" --install

# Grok Build's official Homebrew cask installs its signed release binary as
# both `grok` and the vendor's `agent` alias. Keep this phase to the native
# CLI/TUI itself: AgentUsage's Grok inventory does not activate harness credentials,
# and AgentLaunch and Herdr do not support Grok sessions yet.
printf 'Installing or upgrading the Grok Build CLI/TUI (standalone; no fleet launch integration).\n'
install_or_upgrade_cask grok-build

# Keep Claude's vendor staging under macOS's stable cache root. This machine's
# ~/.cache may be a machine-managed link to removable scratch storage, while
# the native installer needs its cache path available during every converge.
XDG_CACHE_HOME="$HOME/Library/Caches" install_official "Claude Code" \
    https://claude.ai/install.sh \
    /bin/bash

printf 'Installing Codex CLI with its official installer.\n'
/usr/bin/curl -fsSL https://chatgpt.com/codex/install.sh \
    | CODEX_NON_INTERACTIVE=1 /bin/sh

# Keep Plannotator's harness-facing resources inside AgentStart's fixed set.
# --minimal asks the upstream installer for only its checksummed release binary:
# no plan-mode hooks, ambient skills, slash commands, or managed runtimes.
# AgentStart installs the agent-terminal runtime explicitly so the
# embedded Agent tab works, while the exact release's portable core skills
# enter the fixed resources below.
install_official "Plannotator $plannotator_version" \
    https://plannotator.ai/install.sh \
    /bin/bash -s -- --version "v$plannotator_version" --minimal --non-interactive
plannotator_bin="$HOME/.local/bin/plannotator"
[ -x "$plannotator_bin" ] \
    || die "Plannotator did not install an executable at $plannotator_bin"
plannotator_version_output=$("$plannotator_bin" --version)
[ "$plannotator_version_output" = "plannotator $plannotator_version" ] \
    || die "Plannotator version mismatch: expected $plannotator_version, got $plannotator_version_output"
printf 'Installing the Plannotator agent-terminal runtime.\n'
"$plannotator_bin" install-runtime agent-terminal

# Zig builds Native SDK applications, and the machine's Brewfile alone cannot
# guarantee it is present in a session that only runs this script (intentional
# duplicate of that Brewfile).
printf 'Installing or upgrading Zig for Native SDK packaging (intentional duplicate of the machine'\''s Brewfile).\n'
install_or_upgrade_formula zig

# fxnk owns Fx fork maintenance and the hardened integration installer.
# AgentStart decides that the harness is present and invokes that public
# contract without reaching into its checkout or duplicating its branch logic.
fxnk_installer="$code_root/fxnk/scripts/install.sh"
[ -x "$fxnk_installer" ] || die "fxnk installer is unavailable: $fxnk_installer"
printf 'Installing Fx through the fxnk integration contract.\n'
"$fxnk_installer" --install --sha "$fx_integration_sha"

# llm is an AI CLI, so it is AgentStart's outright — moved out of the
# machine's Brewfile rather than duplicated from it.
printf 'Installing or upgrading the llm CLI.\n'
install_or_upgrade_formula llm

# Hunk is a review-first diff TUI for agent-authored changesets. Homebrew owns
# its binary and update path; the version-matched hunk-review skill is copied
# from the installed formula later, after npx is available.
printf 'Installing or upgrading Hunk.\n'
install_or_upgrade_formula hunk

# Terminal Control has no Homebrew formula or release binaries: its supported
# CLI install builds the crates.io release. Rustup gives that build a current
# stable compiler without changing the operator's default toolchain, and its
# libghostty-vt dependency requires the exact Zig 0.15 line below. Cargo's
# install root remains ~/.local so its release bookkeeping and
# upgrades stay native. AgentStart temporarily restores the upstream binary to
# Cargo's expected path before an upgrade, then retains it under libexec and
# puts the detached-start shim back at the public path.
printf 'Installing or upgrading Rustup for the Terminal Control build.\n'
install_or_upgrade_formula rustup
rustup_bin="$brew_prefix/opt/rustup/bin/rustup"
[ -x "$rustup_bin" ] \
    || die "Homebrew's keg-only Rustup executable is missing: $rustup_bin"

# Terminal Control's libghostty-vt dependency pins the Zig 0.15 line, while
# the tracked `zig` formula above has moved past it. Keep the keg-only line
# beside current Zig for that source build.
printf 'Installing or upgrading Zig 0.15 for the Terminal Control build (keg-only, beside the tracked zig).\n'
install_or_upgrade_formula zig@0.15

printf 'Installing the stable Rust toolchain for Terminal Control.\n'
"$rustup_bin" toolchain install stable --profile minimal

termctrl_bin="$HOME/.local/bin/termctrl"
termctrl_real_dir="$HOME/.local/libexec/agentstart/terminal-control"
termctrl_real="$termctrl_real_dir/termctrl"
termctrl_shim="$repo_root/config/terminal-control/termctrl"

# Cargo records the public bin path in its install metadata. Restore the real
# executable before asking Cargo to converge the crate so a same-version run
# remains cheap and an available upgrade can replace the binary normally.
if [ -f "$termctrl_bin" ] &&
    grep -F -m 1 '# AgentStart-managed Terminal Control shim.' \
        "$termctrl_bin" >/dev/null 2>&1; then
    [ -x "$termctrl_real" ] \
        || die "Terminal Control shim is installed but its upstream executable is missing: $termctrl_real"
    install -m 0755 "$termctrl_real" "$termctrl_bin"
fi

printf 'Building and installing Terminal Control from its locked crates.io release.\n'
PATH="$brew_prefix/opt/zig@0.15/bin:$PATH" \
    "$rustup_bin" run stable cargo install --locked --root "$HOME/.local" terminal-control
[ -x "$termctrl_bin" ] \
    || die "Terminal Control did not install an executable at $termctrl_bin"
terminal_control_version_output=$("$termctrl_bin" --version)
terminal_control_version=$terminal_control_version_output
terminal_control_version=${terminal_control_version##* }
[[ "$terminal_control_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] \
    || die "could not resolve the installed Terminal Control version"

printf 'Installing AgentStart detached-start shim for Terminal Control.\n'
mkdir -p "$termctrl_real_dir"
install -m 0755 "$termctrl_bin" "$termctrl_real"
install -m 0755 "$termctrl_shim" "$termctrl_bin"
[ "$("$termctrl_bin" --version)" = "$terminal_control_version_output" ] \
    || die "Terminal Control shim does not reach the installed upstream release"

# Herdr is the terminal multiplexer agent sessions run inside — an AI tool by
# the boundary rubric, so AgentStart's, not the machine's. Homebrew's stable
# formula owns its binary and normal update path; AgentStart still converges
# the fleet integrations, plugin, behavior config, and bundled skill below.
# Package-manager replacement cannot use Herdr's live handoff. Inspect every
# default/named socket before Homebrew can change the installed client bytes.
herdr_socket_state=$("$script_dir/herdr-socket-state") \
    || die "inspecting Herdr server sockets before Homebrew convergence failed"
herdr_upgrade_allowed="${AGENTSTART_HERDR_ALLOW_UPGRADE:-0}"
case "$herdr_upgrade_allowed" in
    0|1) ;;
    *) die "AGENTSTART_HERDR_ALLOW_UPGRADE must be 0 or 1" ;;
esac
herdr_formula_installed=0
if "$brew_bin" list --formula --versions herdr >/dev/null 2>&1; then
    herdr_formula_installed=1
fi
case "$herdr_socket_state" in
    inactive)
        if [ "$herdr_formula_installed" -eq 0 ]; then
            printf 'Installing Herdr from the official stable formula.\n'
            install_or_upgrade_formula herdr
        elif [ "$herdr_upgrade_allowed" -eq 1 ]; then
            printf 'Installing or upgrading Herdr from the official stable formula.\n'
            install_or_upgrade_formula herdr
        else
            printf 'Preserving the installed Homebrew Herdr version; set AGENTSTART_HERDR_ALLOW_UPGRADE=1 for an inactive maintenance run.\n'
        fi
        ;;
    present)
        printf 'Deferring Homebrew Herdr installation or upgrade while a server socket is present.\n'
        ;;
    uncertain)
        printf 'Deferring Homebrew Herdr installation or upgrade because server socket state is uncertain.\n'
        ;;
    *) die "unexpected Herdr socket state: $herdr_socket_state" ;;
esac

herdr_bin="$brew_prefix/bin/herdr"
[ -x "$herdr_bin" ] \
    || die "Homebrew Herdr is unavailable; stop any remaining server and rerun the installer"
herdr_protocol=$("$herdr_bin" status client 2>/dev/null \
    | awk '$1 == "protocol:" { print $2; exit }')
case "$herdr_protocol" in
    ''|*[!0-9]*) die "could not read the Homebrew Herdr client protocol" ;;
esac
[ "$herdr_protocol" -ge 20 ] \
    || die "Homebrew Herdr protocol $herdr_protocol is below the fleet minimum 20"

# The harness integrations wire each agent into Herdr. Claude's and Codex's
# report session identity (for native restore) and deliberately leave lifecycle
# to Herdr's screen detection. They install after both harness CLIs above, because each one
# writes inside a harness's own configuration directory that those installers
# create. Reinstalled unconditionally on every run: a herdr upgrade can leave
# an integration stale — the reason `herdr integration status --outdated-only`
# exists — and reinstalling is how it converges. Unlike the harness
# configuration this installer writes itself, these files belong to Herdr, so
# ownership and conflict rules are its installer's to enforce, exactly as they
# are for a fleet checkout's own installer. Herdr supports more harnesses, and
# adding one here is a deliberate edit.
install_herdr_integrations() {
    local harness

    for harness in claude codex; do
        printf 'Installing the herdr %s integration.\n' "$harness"
        if [ "$harness" = claude ]; then
            CLAUDE_CONFIG_DIR="$HOME/.claude" "$herdr_bin" integration install "$harness" \
                || die "herdr integration install failed: $harness"
        elif [ "$harness" = codex ]; then
            CODEX_HOME="$HOME/.codex" "$herdr_bin" integration install "$harness" \
                || die "herdr integration install failed: $harness"
        fi
    done
}

install_herdr_integrations

# Herdr's v8 Codex hook can miss the first SessionStart identity report. Keep
# the known-working fallback in AgentStart source control and reinstall it
# after Herdr has converged its own hook. The fallback retains the already-
# trusted command path, acts only for AgentLaunch descendants inside Herdr,
# and self-disables as soon as the managed integration version exceeds 8.
"$script_dir/install-herdr-codex-session-fallback" --install

# AgentSurface's herdr plugin (the titled fleet TUI popups plus tab naming from
# a conversation's first prompt) registers by link, not copy: herdr records the
# checkout path, so a changed checkout needs no relink and relinking the same
# path is a safe converge. A resident server may temporarily speak a newer
# protocol than the installed client after an upgrade. Preserve its existing
# link and defer the idempotent relink until the operator's natural server
# restart rather than stopping panes to force it.
# The registered plugin belongs to herdr; the plugin directory belongs to the
# agentsurface checkout, whose absence is a skip exactly as in
# install-agent-clis.
install_herdr_plugins() {
    local plugin_root="$code_root/agentsurface/plugin"
    local link_output=''

    if [ ! -f "$plugin_root/herdr-plugin.toml" ]; then
        printf 'AgentStart installer: no agentsurface plugin at %s; skipping.\n' "$plugin_root"
        return 0
    fi
    printf 'Linking the agentsurface herdr plugin.\n'
    if ! link_output=$("$herdr_bin" plugin link "$plugin_root" 2>&1); then
        case "$link_output" in
            *'"code":"protocol_mismatch"'*)
                printf 'AgentStart installer: preserving the existing agentsurface plugin link; relink deferred until the natural Herdr server restart: %s\n' \
                    "$link_output" >&2
                return 0
                ;;
        esac
        printf '%s\n' "$link_output" >&2
        die "herdr plugin link failed: $plugin_root"
    fi

    # A successful link returns the entire plugin record as JSON. The status
    # line above is sufficient for convergence; replaying that payload can
    # fail with EAGAIN when an unattended caller has a nonblocking stdout.
}

install_herdr_plugins

# smolmux owns its consumer and operator source installation. AgentStart
# delegates the editable command, exact Companion pin, and doctor verification
# to that entrypoint. Smolmux sessions run arbitrary commands and own no Fx pin.
# A machine without the checkout skips; a present checkout that fails to install
# is a real error.
smolmux_root="$code_root/smolmux"
if [ -f "$smolmux_root/package.json" ]; then
    [ -x "$smolmux_root/scripts/install.sh" ] \
        || die "smolmux checkout has no executable scripts/install.sh; update $smolmux_root"
    printf 'Installing smolmux through its canonical source installer.\n'
    SMOLMUX_INSTALL_BIN_DIR="$HOME/.local/bin" \
        "$smolmux_root/scripts/install.sh" --install \
        || die "smolmux source installation failed"
else
    printf 'AgentStart installer: no smolmux checkout at %s; skipping smolmux.\n' \
        "$smolmux_root"
fi

# smolmux never writes its configuration, so its Herdr-compatible key subset can
# stay linked directly to AgentStart's tracked operator configuration.
printf "Linking AgentStart's smolmux configuration.\n"
"$script_dir/smolmux-config" install

# Herdr's live configuration is rendered rather than linked, because Herdr
# writes its own keys into it and neither checkout may become program-written
# state. The helper validates the candidate before an atomic replacement and
# reloads a running server. It carries no palette: Herdr's `terminal` theme
# follows the terminal, which runs its own default colors.
printf "Rendering AgentStart's Herdr configuration.\n"
AGENTSTART_HERDR_BIN="$herdr_bin" "$script_dir/herdr-config" install

command -v npm >/dev/null 2>&1 || die "npm is required to install the Native SDK CLI"

# The native-sdk skill documents the 0.7 line and its agent helpers are
# version-matched to it, so pin that line here instead of tracking latest.
native_sdk_version=0.7
printf 'Installing the Native SDK CLI %s and its version-matched agent helpers.\n' \
    "$native_sdk_version"
npm install --global "@native-sdk/cli@$native_sdk_version"

# agent-browser is the driver shared by Agentbrowse and Agentscrape. It is
# pinned rather than tracked: Agentbrowse implements this release's provider
# protocol, and Agentscrape resolves the stable candidate below before PATH.
# Raising this version means verifying both consumers against the new build.
agent_browser_version=0.33.2
printf 'Installing agent-browser %s for Agentbrowse and Agentscrape.\n' \
    "$agent_browser_version"
npm install --global "agent-browser@$agent_browser_version"

# Publish the stable candidate Agentscrape resolves before falling back to PATH.
# Both consumers run under launchd, whose minimal PATH never reaches a tool
# installed under a Node version manager, and the version-manager path itself
# changes with every Node upgrade. Resolve npm's physical global entrypoint
# before replacing the stable address, so a prior stable link cannot select
# itself through PATH.
printf 'Linking the stable agent-browser candidate into ~/.local/bin.\n'
agent_browser_npm_prefix=$(npm prefix --global) \
    || die "could not resolve npm's global prefix after installing agent-browser"
link_agent_browser "$agent_browser_npm_prefix"

command -v npx >/dev/null 2>&1 || die "npx is required to install agent skills"

printf 'Installing the common skill discovery helper.\n'
install_private_skill_pack https://github.com/vercel-labs/skills find-skills

printf 'Installing the web interface review skill.\n'
install_private_skill_pack https://github.com/vercel-labs/agent-skills web-design-guidelines

printf 'Installing Vercel React engineering guidance.\n'
install_private_skill_pack https://github.com/vercel-labs/agent-skills vercel-react-best-practices

printf 'Installing the official Vercel AI SDK and AI Elements skills.\n'
install_private_skill_pack https://github.com/vercel/ai ai-sdk
install_private_skill_pack https://github.com/vercel/ai-elements ai-elements

printf 'Installing the official shadcn skill.\n'
install_private_skill_pack https://github.com/shadcn/ui shadcn

printf 'Installing the Native SDK discovery skill.\n'
install_private_skill_pack https://github.com/vercel-labs/native native-sdk

# Use the tagged core subtree rather than repository head or Claude's
# injection-form variants. One portable set is rendered into both managed
# harnesses, and it must never teach commands newer than the installed binary.
plannotator_skill_source="https://github.com/backnotprop/plannotator/tree/v${plannotator_version}/apps/skills/core"
printf 'Installing the version-matched Plannotator skills.\n'
install_private_skill_pack "$plannotator_skill_source" \
    plannotator plannotator-review plannotator-annotate plannotator-last

# Bind the runbook to the same release as the CLI. The skills CLI accepts a
# GitHub ref suffix, and Terminal Control publishes v<crate-version> tags, so a
# new crates.io release and its skill converge together instead of teaching a
# command surface from repository head against an older installed binary.
printf 'Installing the version-matched Terminal Control skill.\n'
install_private_skill_pack \
    "anomalyco/terminal-control@v$terminal_control_version" terminal-control

# Hunk ships its agent-facing review surface inside the installed binary. Use
# `hunk skill path` as the authority instead of copying the GitHub head: the
# skill describes the exact `hunk session` commands this build accepts. The
# resolved package root already has the skills/<name>/SKILL.md shape consumed
# by the fixed-resource renderer. Its description handles discovery
# for live Hunk sessions and interactive diff review.
install_hunk_skill() {
    local skill_file skill_dir pack_root

    skill_file=$(hunk skill path hunk-review) \
        || die "locating the bundled Hunk review skill failed"
    [ -f "$skill_file" ] \
        || die "the installed Hunk review skill is missing: $skill_file"

    skill_dir=$(cd -P -- "$(dirname -- "$skill_file")" && pwd) \
        || die "resolving the bundled Hunk review skill directory failed"
    skill_file="$skill_dir/${skill_file##*/}"
    [ "${skill_dir##*/}" = hunk-review ] \
        || die "the installed Hunk review skill has an unexpected path: $skill_file"
    pack_root=$(cd -P -- "$skill_dir/../.." && pwd) \
        || die "resolving the installed Hunk skill pack failed"
    [ "$pack_root/skills/hunk-review/SKILL.md" = "$skill_file" ] \
        || die "the installed Hunk review skill does not match its pack root: $skill_file"

    install_private_skill_pack "$pack_root" hunk-review
}

printf 'Installing the Hunk review skill from the installed binary.\n'
install_hunk_skill

# The surface skill — herdr is the fleet's shared launch surface — ships
# inside the herdr binary (`herdr --skill`), so the installed
# skill converges with the installed build on every run, exactly like the
# harness integrations above, and never tracks a different release than the
# stable formula. The rendered pack lives
# in a managed state root shaped like a checkout (skills/herdr/) so the same
# `skills add` mechanism ships it into the fixed private resources. Its
# description covers explicit Herdr work.
install_herdr_skill() {
    local pack_root="$HOME/.local/share/agentstart/herdr-skill"
    local skill_dir="$pack_root/skills/herdr"

    mkdir -p "$skill_dir"
    "$herdr_bin" --skill >"$skill_dir/SKILL.md" \
        || die "rendering the herdr skill from the installed binary failed"
    [ -s "$skill_dir/SKILL.md" ] \
        || die "the installed herdr rendered an empty skill"
    install_private_skill_pack "$pack_root" herdr
}

printf 'Installing the herdr surface skill from the installed binary.\n'
install_herdr_skill

printf 'Verifying the installed Native SDK agent documentation helpers.\n'
native skills list >/dev/null

# The fleet CLIs install by their own hardened
# contract (frozen deps, ~/.local/bin symlink, deployed-SHA receipt). AgentStart
# only invokes it; a machine without a checkout skips inside the script, so
# only a present-but-broken checkout fails here.
"$script_dir/agentvoice-config" install

agent_clis_status=0
"$script_dir/install-agent-clis" || agent_clis_status=$?
if [ "$agent_clis_status" -eq 0 ]; then
    bun "$script_dir/agentvoice-network.ts" --install
fi
if [ "$agent_clis_status" -ne 0 ]; then
    printf 'AgentStart installer: agent CLIs install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or scripts/install-agent-clis.\n' \
        "$agent_clis_status" >&2
    exit "$agent_clis_status"
fi

"$script_dir/install-agentlaunch-shims"
"$script_dir/agentstart" config apply --notify

# Agentbrowse and agent-browser do not write these configs during normal
# browsing, so the operator defaults can stay linked directly to AgentStart's
# tracked sources. Run both after the fleet CLI loop: a successful full
# converge must not select the provider before its command and manual recovery
# helper install successfully.
printf "Linking AgentStart's ordered agentbrowse deployment configuration.\n"
"$script_dir/agentbrowse-config" install
printf "Linking AgentStart's default agentbrowse provider configuration.\n"
"$script_dir/agent-browser-config" install

# agentmux reads an instance's config at start and never writes it, so the
# operator's default instance config stays linked to AgentStart's tracked
# copy. After the fleet CLI loop, which installs agentmux and the agentwork
# setup the config names.
printf "Linking AgentStart's agentmux instance configuration.\n"
"$script_dir/agentmux-config" install

# agentchats — the coding-agent session search CLI — installs by the
# agentchats checkout's own contract: the editable CLI link plus the local
# SQLite index it owns end to end over the Claude Code and Codex session
# stores. Its chats skill ships through the agent* checkout skill scan like
# every other tool's. A machine without the checkout skips, like the agent
# CLIs above; a present checkout that fails to install is a real error.
agentchats_root="$code_root/agentchats"
if [ -f "$agentchats_root/scripts/install.sh" ]; then
    agentchats_status=0
    "$agentchats_root/scripts/install.sh" --install || agentchats_status=$?
    if [ "$agentchats_status" -ne 0 ]; then
        printf 'AgentStart installer: agentchats install failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or %s/scripts/install.sh --install.\n' \
            "$agentchats_status" "$agentchats_root" >&2
        exit "$agentchats_status"
    fi
else
    printf 'AgentStart installer: no agentchats checkout at %s; skipping session search.\n' \
        "$agentchats_root"
fi

# Agentdesk's installer owns its Computer Use stdio MCP and desktop skill. It
# never starts a call.
agentdesk_root="$code_root/agentdesk"
if [ -f "$agentdesk_root/scripts/install.sh" ]; then
    agentdesk_status=0
    "$agentdesk_root/scripts/install.sh" --install || agentdesk_status=$?
    if [ "$agentdesk_status" -ne 0 ]; then
        printf 'AgentStart installer: Agentdesk installation failed (exit %s). Fix the reported problem, then rerun scripts/install.sh --install or %s/scripts/install.sh --install.\n' \
            "$agentdesk_status" "$agentdesk_root" >&2
        exit "$agentdesk_status"
    fi
else
    printf 'AgentStart installer: no agentdesk checkout at %s; skipping the Computer Use server.\n' \
        "$agentdesk_root"
fi

# Publish the shared inventory before the gateway starts. The content updater
# uses the same renderer without installing, uninstalling or restarting anything.
converge_repo_content
"$script_dir/install-mcp-gateway" --install

# The fleet's long-running services. This runs after every CLI above, because
# a service is only installed once the binary it supervises exists — a tool
# that is absent is skipped, exactly like its checkout was. The fleet
# checkouts ship the code; this repository decides when it runs. The machine
# layer keeps its own services, which are the reverse-DNS labels.
printf 'Installing the fleet launch agents.\n'
"$script_dir/install-launchagents" --install

# Authorization is never implicit in ordinary convergence. Diagnose the
# receiver and inspectable webhook path after its CLI and resident service
# exist; incomplete state prints an agent-ready handoff while a healthy machine
# remains quiet.
"$script_dir/configure-agentsource-webhooks" --check || true

# Replace only the inspected MCP Funnel route after the authenticated listener
# is healthy.
"$script_dir/install-mcp-gateway" --expose
