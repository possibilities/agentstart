#!/bin/bash

set -euo pipefail

repo_root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agent-browser-link.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT

die() {
    printf 'agent-browser-link fixture: %s\n' "$*" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$repo_root/scripts/agent-browser-link.sh"

npm_prefix="$fixture_root/npm-prefix"
npm_binary="$npm_prefix/lib/node_modules/agent-browser/bin/agent-browser"
stable_link="$fixture_root/home/.local/bin/agent-browser"
mkdir -p "$(dirname "$npm_binary")" "$npm_prefix/bin" "$(dirname "$stable_link")"
printf '#!/bin/sh\nprintf "agent-browser fixture\\n"\n' >"$npm_binary"
chmod 0755 "$npm_binary"
ln -s ../lib/node_modules/agent-browser/bin/agent-browser "$npm_prefix/bin/agent-browser"

# Reproduce the production failure: PATH had already selected the stable link,
# so the old installer replaced it with a link to itself.
ln -s "$stable_link" "$stable_link"
HOME="$fixture_root/home" link_agent_browser "$npm_prefix"
[ "$(readlink "$stable_link")" = "$(realpath "$npm_binary")" ] \
    || die "a pre-existing self-loop was not repaired to npm's physical binary"
[ "$("$stable_link")" = "agent-browser fixture" ] \
    || die "the repaired stable link did not execute npm's physical binary"

independent_home="$fixture_root/independent-home"
independent_target="$independent_home/.local/bin/agent-browser"
mkdir -p "$(dirname "$independent_target")"
printf 'operator-owned\n' >"$independent_target"
if (HOME="$independent_home" link_agent_browser "$npm_prefix") 2>/dev/null; then
    die "an independent regular target was replaced"
fi
[ "$(cat "$independent_target")" = "operator-owned" ] \
    || die "an independent regular target changed"

nonexec_prefix="$fixture_root/nonexec-prefix"
mkdir -p "$nonexec_prefix/bin"
printf 'not executable\n' >"$nonexec_prefix/bin/agent-browser"
if (HOME="$fixture_root/nonexec-home" link_agent_browser "$nonexec_prefix") 2>/dev/null; then
    die "a non-executable npm entrypoint was accepted"
fi
[ ! -e "$fixture_root/nonexec-home/.local/bin/agent-browser" ] \
    || die "a target was published for a non-executable npm entrypoint"

printf 'agent-browser link tests passed\n'
