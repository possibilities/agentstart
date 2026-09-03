#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/agentmux-config"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agentmux-config.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'agentmux-config test: %s\n' "$*" >&2
    exit 1
}

source_config="$test_root/source"
target_config="$test_root/home/.config/agentmux/instances/default"
cat >"$source_config" <<'EOF2'
setup = /nowhere

[panel left]
command = tray
EOF2

export HOME="$test_root/home"
export AGENTSTART_AGENTMUX_CONFIG_SOURCE="$source_config"
export AGENTSTART_AGENTMUX_CONFIG_TARGET="$target_config"

"$helper" install
[ -L "$target_config" ] || fail "install did not link the agentmux instance config"
cmp -s "$source_config" "$target_config" || fail "linked agentmux instance config does not resolve to the tracked source"

# The converge is rerunnable.
"$helper" install

# Independent regular files are never replaced.
independent_target="$test_root/independent/config"
mkdir -p "$(dirname -- "$independent_target")"
printf 'keep me\n' >"$independent_target"
if AGENTSTART_AGENTMUX_CONFIG_TARGET="$independent_target" "$helper" install >/dev/null 2>&1; then
    fail "an independent regular agentmux instance config was replaced"
fi
[ "$(cat "$independent_target")" = "keep me" ] || fail "independent agentmux instance config changed"

empty_target="$test_root/empty/config"
mkdir -p "$(dirname -- "$empty_target")"
: >"$empty_target"
if AGENTSTART_AGENTMUX_CONFIG_TARGET="$empty_target" "$helper" install >/dev/null 2>&1; then
    fail "an independent empty agentmux instance config was replaced"
fi
[ -f "$empty_target" ] && [ ! -L "$empty_target" ] || fail "independent empty agentmux instance config changed"

# The tracked config names the tray app for the left panel and a command for
# every other panel, so a fresh machine shows something on each surface.
# A panel's command is the `command = ...` line inside its [panel NAME]
# section, so the check reads section by section.
section_has() {
    awk -v header="[panel $1]" -v want="$2" '
        $0 == header { inside = 1; next }
        /^\[/ { inside = 0 }
        inside && $0 ~ want { found = 1 }
        END { exit !found }
    ' "$root/config/agentmux/instances/default"
}
for panel in left drawer dock right; do
    section_has "$panel" '^command = [^[:space:]]' \
        || fail "tracked agentmux instance config has no command for the $panel panel"
done
section_has left '^command = tray$' \
    || fail "tracked agentmux instance config does not put the tray app in the left panel"
grep -Fqx 'setup = ~/code/agentwork' "$root/config/agentmux/instances/default" \
    || fail "tracked agentmux instance config does not name agentwork as its setup"
# The same file is agentmux's config for the instance, so the operator's
# prefix and harness defaults live here and nowhere else.
grep -Fqx 'prefix = ctrl+space' "$root/config/agentmux/instances/default" \
    || fail "tracked agentmux instance config does not carry the operator's agentmux prefix"
grep -Fq 'instance = ' "$root/config/agentmux/instances/default" \
    && fail "tracked agentmux instance config names an instance; the file's name is the instance"

printf 'agentmux-config tests passed\n'
