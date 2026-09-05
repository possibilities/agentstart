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
# The fixture loader stands in for the agentbrowse checkout so the probe runs
# the same way on every machine, with or without a real checkout beside it.
export AGENTSTART_AGENTBROWSE_CHECKOUT="$root/tests/fixtures/agentbrowse-checkout"

"$helper" install
[ -L "$target_config" ] || fail "install did not link the agentbrowse config"
cmp -s "$source_config" "$target_config" \
    || fail "linked agentbrowse config does not resolve to the tracked source"
/usr/bin/jq -e '
    .version == 2 and
    (.backends | map(.id)) == ["artbird", "apple-container-local"] and
    .backends[0].video == {"fps": 60, "targetBitrateBps": 4792320, "keyframeMaxDistance": 60} and
    (.backends[1] | has("video") | not) and
    .backends[1].maxTargets == 1 and
    .backends[1].accessMode == "loopback" and
    .backends[1].cpus == 2 and
    .backends[1].memory == "6G" and
    .images.defaultImage == "docker.io/onkernel/chromium-headful@sha256:da9ee68cb9d2de0b3c26885ff3bdcf04c944254a36eb127219028ac017ff56f3" and
    .browser.video == {
        "screenRefreshRate": 60,
        "fps": 30,
        "cpuUsed": 4,
        "threads": 4,
        "targetBitrateBps": 2396160,
        "keyframeMaxDistance": 30
    }
' "$target_config" >/dev/null \
    || fail "installed config does not declare the locked fallback and Live View capture policy"

# The converge is rerunnable.
"$helper" install

# A source that drifts from the locked Live View capture policy is refused
# before anything is linked: the Apple backend must not carry an override, the
# shared policy must stay at 30 fps capture, and neither block may go missing.
drifted_source="$test_root/drifted-source.json"
drifted_target="$test_root/drifted-home/.config/agentbrowse/config.json"
for drift_filter in \
    '.backends[1].video = {"fps": 60}' \
    '.browser.video.fps = 60' \
    'del(.browser.video)' \
    'del(.backends[0].video)'; do
    /usr/bin/jq "$drift_filter" "$root/config/agentbrowse/config.json" >"$drifted_source"
    if drift_output=$(AGENTSTART_AGENTBROWSE_CONFIG_SOURCE="$drifted_source" \
        AGENTSTART_AGENTBROWSE_CONFIG_TARGET="$drifted_target" \
        "$helper" install 2>&1); then
        fail "a drifted Live View capture policy was linked: $drift_filter"
    fi
    printf '%s\n' "$drift_output" | grep -F 'Live View capture policy' >/dev/null \
        || fail "capture policy refusal did not name the policy: $drift_output"
    [ ! -e "$drifted_target" ] && [ ! -L "$drifted_target" ] \
        || fail "a refused capture policy still linked a config: $drift_filter"
done

# A config the deployed CLI's own loader rejects is refused before it is
# linked, and the refusal carries the loader's reason. This is the drift that
# took the browser fleet down on 2026-09-05: the tracked config ran ahead of the
# deployed agentbrowse, whose Apple backend still requires exactly one target.
ahead_source="$test_root/ahead-source.json"
ahead_target="$test_root/ahead-home/.config/agentbrowse/config.json"
/usr/bin/jq '.backends[1].maxTargets = 1000' "$root/config/agentbrowse/config.json" >"$ahead_source"
if ahead_output=$(AGENTSTART_AGENTBROWSE_CONFIG_SOURCE="$ahead_source" \
    AGENTSTART_AGENTBROWSE_CONFIG_TARGET="$ahead_target" \
    "$helper" install 2>&1); then
    fail "a config the deployed loader rejects was linked"
fi
printf '%s\n' "$ahead_output" | grep -F 'deployed agentbrowse rejects the tracked config' >/dev/null \
    || fail "loader refusal did not say the deployed CLI rejects the config: $ahead_output"
printf '%s\n' "$ahead_output" | grep -F 'maxTargets must be 1' >/dev/null \
    || fail "loader refusal did not carry the loader's reason: $ahead_output"
[ ! -e "$ahead_target" ] && [ ! -L "$ahead_target" ] \
    || fail "a config the deployed loader rejects still linked"

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
