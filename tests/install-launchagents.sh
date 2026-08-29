#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-launchagents.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fail() {
    printf 'install-launchagents test: %s\n' "$*" >&2
    exit 1
}

test_home="$test_root/home"
launch_agents="$test_home/Library/LaunchAgents"
bin_dir="$test_home/.local/bin"
state_dir="$test_home/.local/state"
mkdir -p "$launch_agents" "$bin_dir" "$state_dir"

printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentattention"
chmod +x "$bin_dir/agentattention"

legacy_label="com.$(id -un).agentattention"
legacy_plist="$launch_agents/$legacy_label.plist"
cat >"$legacy_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$legacy_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/bun</string>
        <string>$test_home/code/agentattention/src/cli.ts</string>
        <string>serve</string>
        <string>--config</string>
        <string>$test_home/.config/agentattention/config.json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>$test_home/.local/state/agentattention/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$test_home/.local/state/agentattention/daemon.error.log</string>
</dict>
</plist>
EOF

run_check() {
    HOME="$test_home" \
        XDG_STATE_HOME="$state_dir" \
        AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
        AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
        AGENTSTART_INSTALL_LAUNCHCTL=none \
        "$root/scripts/install-launchagents" --check
}

plan=$(run_check)
printf '%s\n' "$plan" | grep -F "replace $legacy_label" >/dev/null \
    || fail "exact legacy Agentattention service was not recognized"
[ ! -e "$launch_agents/agentattention.server.plist" ] \
    || fail "check mode wrote the replacement plist"

/usr/bin/python3 - "$legacy_plist" <<'PYTHON'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as handle:
    value = plistlib.load(handle)
value["ThrottleInterval"] = 6
with open(path, "wb") as handle:
    plistlib.dump(value, handle)
PYTHON

if output=$(run_check 2>&1); then
    fail "modified legacy Agentattention service was accepted"
fi
printf '%s\n' "$output" | grep -F 'refusing to replace a legacy service this installer does not own' >/dev/null \
    || fail "modified legacy service did not fail with the ownership refusal"

printf 'ok\n'
