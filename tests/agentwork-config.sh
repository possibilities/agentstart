#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/agentwork-config"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agentwork-config.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'agentwork-config test: %s\n' "$*" >&2
    exit 1
}

source_config="$test_root/source"
target_config="$test_root/home/.config/agentwork/config"
cat >"$source_config" <<'EOF2'
instance = default
tray = agentwork tray
EOF2

export HOME="$test_root/home"
export AGENTSTART_AGENTWORK_CONFIG_SOURCE="$source_config"
export AGENTSTART_AGENTWORK_CONFIG_TARGET="$target_config"

"$helper" install
[ -L "$target_config" ] || fail "install did not link the agentwork config"
cmp -s "$source_config" "$target_config" || fail "linked agentwork config does not resolve to the tracked source"

# The converge is rerunnable.
"$helper" install

# Independent regular files are never replaced.
independent_target="$test_root/independent/config"
mkdir -p "$(dirname -- "$independent_target")"
printf 'keep me\n' >"$independent_target"
if AGENTSTART_AGENTWORK_CONFIG_TARGET="$independent_target" "$helper" install >/dev/null 2>&1; then
    fail "an independent regular agentwork config was replaced"
fi
[ "$(cat "$independent_target")" = "keep me" ] || fail "independent agentwork config changed"

empty_target="$test_root/empty/config"
mkdir -p "$(dirname -- "$empty_target")"
: >"$empty_target"
if AGENTSTART_AGENTWORK_CONFIG_TARGET="$empty_target" "$helper" install >/dev/null 2>&1; then
    fail "an independent empty agentwork config was replaced"
fi
[ -f "$empty_target" ] && [ ! -L "$empty_target" ] || fail "independent empty agentwork config changed"

# The tracked config names the Tray app for the Tray column and a command for
# every other part, so a fresh machine shows something on each surface.
for key in tray tray-slot workspace-pane right-tray; do
    grep -Eq "^$key = [^[:space:]]" "$root/config/agentwork/config" \
        || fail "tracked agentwork config has no command for $key"
done
grep -Fqx 'tray = agentwork tray' "$root/config/agentwork/config" \
    || fail "tracked agentwork config does not put the Tray app in the Tray column"

printf 'agentwork-config tests passed\n'
