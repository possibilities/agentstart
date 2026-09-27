#!/bin/bash
set -euo pipefail
root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-retire.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
bin="$fixture/bin"
config="$fixture/config"
code="$fixture/code"
mkdir -p "$bin" "$config/agentmux/instances" "$code"
ln -s "$code/agenthud/src/main.ts" "$bin/agenthud"
ln -s "$code/codex-viewer/bin/codex-viewer" "$bin/codex-viewer"
ln -s "$fixture/foreign" "$bin/agentgrok"
printf 'independent\n' >"$bin/agentkeys"
printf '#!/usr/bin/env bash\n# codex-swap-installer-owned:v1\nexec /opt/homebrew/bin/node %s/codex-swap/src/cli/main.ts "$@"\n' "$code" >"$bin/codex-swap"
ln -s "$code/agentstart/config/agentmux/instances/default.yaml" "$config/agentmux/instances/default.yaml"

run() {
    AGENTSTART_CODE_ROOT="$code" AGENTSTART_RETIRED_BIN_DIR="$bin" \
        AGENTSTART_RETIRED_CONFIG_ROOT="$config" \
        "$root/scripts/retire-archived-checkouts" "$@"
}
plan=$(run --check)
printf '%s\n' "$plan" | grep -F 'would retire command link:' >/dev/null
[ -L "$bin/agenthud" ] && [ -L "$config/agentmux/instances/default.yaml" ]
run --apply >/dev/null
[ ! -e "$bin/agenthud" ] && [ ! -L "$bin/agenthud" ]
[ ! -e "$bin/codex-viewer" ] && [ ! -L "$bin/codex-viewer" ]
[ ! -e "$bin/codex-swap" ]
[ ! -e "$config/agentmux/instances/default.yaml" ]
[ -L "$bin/agentgrok" ] && [ -f "$bin/agentkeys" ]
run --apply >/dev/null
