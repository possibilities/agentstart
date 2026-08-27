#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/agent-browser-config"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agent-browser-config.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'agent-browser-config test: %s\n' "$*" >&2
    exit 1
}

source_config="$test_root/source.json"
target_config="$test_root/home/.agent-browser/config.json"
cp "$root/config/agent-browser/config.json" "$source_config"

export HOME="$test_root/home"
export AGENTSTART_AGENT_BROWSER_CONFIG_SOURCE="$source_config"
export AGENTSTART_AGENT_BROWSER_CONFIG_TARGET="$target_config"

"$helper" install
[ -L "$target_config" ] || fail "install did not link the agent-browser config"
cmp -s "$source_config" "$target_config" \
    || fail "linked agent-browser config does not resolve to the tracked source"
/usr/bin/jq -e '
    .provider == "artbird" and
    (.plugins == [{
        "name": "artbird",
        "command": "agentbrowse",
        "args": ["provider"],
        "capabilities": ["browser.provider"]
    }])
' "$target_config" >/dev/null \
    || fail "installed config does not select the agentbrowse Artbird provider"

# The converge is rerunnable.
"$helper" install

# Independent files are never replaced, even when empty.
full_target="$test_root/independent-full/config.json"
empty_target="$test_root/independent-empty/config.json"
for independent_target in "$full_target" "$empty_target"; do
    mkdir -p "$(dirname -- "$independent_target")"
done
printf 'keep me\n' >"$full_target"
: >"$empty_target"
for independent_target in "$full_target" "$empty_target"; do
    if AGENTSTART_AGENT_BROWSER_CONFIG_TARGET="$independent_target" \
        "$helper" install >/dev/null 2>&1; then
        fail "an independent regular agent-browser config was replaced"
    fi
    [ -f "$independent_target" ] && [ ! -L "$independent_target" ] \
        || fail "independent agent-browser config changed"
done

# A superficially valid plugin array without the default provider is rejected.
invalid_source="$test_root/invalid.json"
printf '{"plugins":[]}\n' >"$invalid_source"
if AGENTSTART_AGENT_BROWSER_CONFIG_SOURCE="$invalid_source" \
    AGENTSTART_AGENT_BROWSER_CONFIG_TARGET="$test_root/invalid-target.json" \
    "$helper" install >/dev/null 2>&1; then
    fail "invalid agent-browser provider config was accepted"
fi

printf 'agent-browser-config tests passed\n'
