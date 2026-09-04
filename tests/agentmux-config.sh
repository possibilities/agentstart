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
target_config="$test_root/home/.config/agentmux/instances/default.yaml"
cat >"$source_config" <<'EOF2'
setup: /nowhere
panels:
  left:
    command: tray
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

# The tracked config puts the tray app in the left panel; the other panels
# name no command and show agentmux's placeholder. The file is YAML: a
# panel's command is the `command:` line indented under its name under
# `panels:`, so the check reads entry by entry.
tracked="$root/config/agentmux/instances/default.yaml"
panel_has() {
    awk -v panel="  $1:" -v want="$2" '
        /^panels:/ { block = 1; next }
        block && /^[^ ]/ { block = 0 }
        block && $0 == panel { inside = 1; next }
        block && /^  [^ ]/ { inside = 0 }
        inside && $0 ~ want { found = 1 }
        END { exit !found }
    ' "$tracked"
}
for panel in left bottom_drawer dock right; do
    panel_has "$panel" '^    ' \
        || fail "tracked agentmux instance config has no entry for the $panel panel"
done
panel_has left '^    command: tray$' \
    || fail "tracked agentmux instance config does not put the tray app in the left panel"
grep -Fqx 'setup: ~/code/agentwork' "$tracked" \
    || fail "tracked agentmux instance config does not name agentwork as its setup"
# The same file is agentmux's config for the instance, so the operator's
# prefix and harness defaults live here and nowhere else.
grep -Fqx 'prefix: ctrl+space' "$tracked" \
    || fail "tracked agentmux instance config does not carry the operator's agentmux prefix"
grep -Eq '^instance:' "$tracked" \
    && fail "tracked agentmux instance config names an instance; the file's name is the instance"

printf 'agentmux-config tests passed\n'
