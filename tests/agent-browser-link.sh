#!/bin/bash

set -euo pipefail

repo_root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agent-browser-link.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT

die() { printf 'agent-browser-link fixture: %s\n' "$*" >&2; exit 1; }
# shellcheck source=/dev/null
source "$repo_root/scripts/agent-browser-link.sh"

export HOME="$fixture_root/home"
export STACK_STATE_DIR="$fixture_root/state"
binary="$STACK_STATE_DIR/browser/toolchain/current/node_modules/agent-browser/bin/agent-browser-darwin-arm64"
target="$HOME/.local/bin/agent-browser"
mkdir -p "$(dirname "$binary")" "$(dirname "$target")"

# Ordinary convergence never installs a missing release or overwrites an
# independent stable command.
link_agent_browser
[ ! -e "$target" ] || die "missing managed release was published"
printf '#!/bin/sh\nprintf "agent-browser fixture\\n"\n' >"$binary"
chmod 0755 "$binary"
printf 'operator-owned\n' >"$target"
if (link_agent_browser) 2>/dev/null; then die "independent command was replaced"; fi
[ "$(cat "$target")" = operator-owned ] || die "independent command changed"
rm "$target"

link_agent_browser
[ "$(readlink "$target")" = "$binary" ] || die "managed release was not linked"
[ "$("$target")" = 'agent-browser fixture' ] || die "stable link does not execute managed release"

ln -sfn "$HOME/.local/state/agentstack/browser/toolchain/current/node_modules/agent-browser/bin/agent-browser-darwin-arm64" "$target"
link_agent_browser
[ "$(readlink "$target")" = "$binary" ] || die "legacy Stack link was not migrated"

ln -sfn "$fixture_root/foreign" "$target"
if (link_agent_browser) 2>/dev/null; then die "foreign symlink was replaced"; fi
[ "$(readlink "$target")" = "$fixture_root/foreign" ] || die "foreign symlink changed"

printf 'agent-browser link tests passed\n'
