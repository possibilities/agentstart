#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
helper="$root/scripts/agentbrowse-config"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agentbrowse-config.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fail() {
    printf 'agentbrowse-config test: %s\n' "$*" >&2
    exit 1
}

source_config="$test_root/source.json"
target_config="$test_root/home/.config/agentbrowse/config.json"
cp "$root/config/agentbrowse/config.json" "$source_config"

export HOME="$test_root/home"
export AGENTSTART_AGENTBROWSE_CONFIG_SOURCE="$source_config"
export AGENTSTART_AGENTBROWSE_CONFIG_TARGET="$target_config"

"$helper" install
[ -L "$target_config" ] || fail "install did not link the agentbrowse config"
cmp -s "$source_config" "$target_config" \
    || fail "linked agentbrowse config does not resolve to the tracked source"
/usr/bin/jq -e '
    .version == 2 and
    (.backends | map(.id)) == ["artbird", "apple-container-local"] and
    .backends[1].maxTargets == 1 and
    .backends[1].cpus == 2 and
    .backends[1].memory == "6G" and
    .images.defaultImage == "docker.io/onkernel/chromium-headful@sha256:da9ee68cb9d2de0b3c26885ff3bdcf04c944254a36eb127219028ac017ff56f3"
' "$target_config" >/dev/null || fail "installed config does not declare the locked fallback"

# The converge is rerunnable.
"$helper" install

# The one known hand-written version-1 config migrates deliberately.
legacy_target="$test_root/legacy-home/.config/agentbrowse/config.json"
mkdir -p "$(dirname -- "$legacy_target")"
/usr/bin/jq -n --arg home "$HOME" '{
    version: 1,
    docker: {context: "artbird", expectedEndpoint: "ssh://artbird", expectedEngine: "artbird"},
    remote: {host: "artbird", networkAddressCommand: "tailscale ip -4"},
    images: {sourceDirectory: ($home + "/src/kernel-images")},
    browser: {timezone: "America/New_York"},
    provider: {name: "artbird", description: "Manage Kernel browser targets on Artbird"},
    liveView: {labelPrefix: "artbird", username: "kernel", password: "admin", readOnly: false},
    discovery: {commandTimeoutMs: 2000}
}' >"$legacy_target"
AGENTSTART_AGENTBROWSE_CONFIG_TARGET="$legacy_target" "$helper" install
if [ ! -L "$legacy_target" ] || ! cmp -s "$source_config" "$legacy_target"; then
    fail "known version-1 config did not migrate to the tracked link"
fi

# Independent files and links are never replaced.
independent_file="$test_root/independent/config.json"
independent_source="$test_root/independent-source.json"
independent_link="$test_root/independent-link/config.json"
mkdir -p "$(dirname -- "$independent_file")" "$(dirname -- "$independent_link")"
printf '{"version":2,"owner":"someone-else"}\n' >"$independent_file"
printf '{"version":2,"owner":"someone-else"}\n' >"$independent_source"
ln -s "$independent_source" "$independent_link"
for independent_target in "$independent_file" "$independent_link"; do
    if AGENTSTART_AGENTBROWSE_CONFIG_TARGET="$independent_target" \
        "$helper" install >/dev/null 2>&1; then
        fail "an independent agentbrowse config was replaced"
    fi
done
[ -f "$independent_file" ] && [ ! -L "$independent_file" ] \
    || fail "independent agentbrowse config file changed"
[ "$(readlink "$independent_link")" = "$independent_source" ] \
    || fail "independent agentbrowse config link changed"

printf 'agentbrowse-config tests passed\n'
