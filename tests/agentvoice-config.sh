#!/bin/bash
set -euo pipefail
root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agentvoice-config.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export AGENTSTART_AGENTVOICE_CONFIG_SOURCE="$root/config/agentvoice/server.json"
export AGENTSTART_AGENTVOICE_CONFIG_TARGET="$HOME/.config/agentvoice/server.json"
helper="$root/scripts/agentvoice-config"
"$helper" install
"$helper" install
[ -L "$AGENTSTART_AGENTVOICE_CONFIG_TARGET" ]
cmp "$AGENTSTART_AGENTVOICE_CONFIG_SOURCE" "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
rm "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
: > "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
"$helper" install
[ -L "$AGENTSTART_AGENTVOICE_CONFIG_TARGET" ]
rm "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
printf 'keep settings\n' > "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
if "$helper" install >/dev/null 2>&1; then exit 1; fi
[ "$(cat "$AGENTSTART_AGENTVOICE_CONFIG_TARGET")" = 'keep settings' ]
rm "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
ln -s "$test_root/unrelated" "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
if "$helper" install >/dev/null 2>&1; then exit 1; fi
[ "$(readlink "$AGENTSTART_AGENTVOICE_CONFIG_TARGET")" = "$test_root/unrelated" ]
rm "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
: > "$AGENTSTART_AGENTVOICE_CONFIG_TARGET"
ln "$AGENTSTART_AGENTVOICE_CONFIG_TARGET" "$test_root/hardlink"
if "$helper" install >/dev/null 2>&1; then exit 1; fi
python3 - "$root/config/agentvoice/server.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == {
    'allow-full-access': True, 'debug': True,
    'role': '~/code/agentvoice/roles/default',
    'orchestrator': {'model': 'gpt-6-astra', 'effort': 'low'},
}
PY
printf 'agentvoice-config tests passed\n'
