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

rm -- "$legacy_plist"

# Agentweb retirement is ownership-marker exact. Check mode reports the plan
# without mutation; install boots out the loaded broker before any new service
# is bootstrapped, then removes its plist.
broker_plist="$launch_agents/agentweb.broker.plist"
printf '<!-- agentstart-installer-owned: agentweb.broker.v1 -->\n' >"$broker_plist"
broker_plan=$(run_check)
printf '%s\n' "$broker_plan" | grep -F 'agentweb.broker' | grep -F 'would boot out and remove owned plist' >/dev/null \
    || fail "owned retired Agentweb broker was not planned for removal"
[ -f "$broker_plist" ] || fail "check mode removed the retired broker plist"

fake_launchctl="$test_root/launchctl"
launchctl_log="$test_root/launchctl.log"
loaded_marker="$test_root/agentweb-loaded"
cat >"$fake_launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$1" in
    print)
        [ "$2" = "gui/$(id -u)/agentweb.broker" ] && [ -f "$AGENTSTART_TEST_AGENTWEB_LOADED" ]
        ;;
    bootout)
        printf 'bootout %s\n' "$2" >>"$AGENTSTART_TEST_LAUNCHCTL_LOG"
        rm -f -- "$AGENTSTART_TEST_AGENTWEB_LOADED"
        ;;
    bootstrap)
        printf 'bootstrap %s\n' "$3" >>"$AGENTSTART_TEST_LAUNCHCTL_LOG"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$fake_launchctl"
: >"$loaded_marker"

HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL="$fake_launchctl" \
    AGENTSTART_TEST_AGENTWEB_LOADED="$loaded_marker" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$launchctl_log" \
    "$root/scripts/install-launchagents" --install >/dev/null

[ ! -e "$broker_plist" ] || fail "owned retired broker plist survived install"
[ ! -e "$loaded_marker" ] || fail "loaded retired broker was not booted out"
first_launchctl_action=$(sed -n '1p' "$launchctl_log")
[ "$first_launchctl_action" = "bootout gui/$(id -u)/agentweb.broker" ] \
    || fail "retired broker was not stopped before service convergence: $first_launchctl_action"

# A foreign occupant is reported but preserved in check mode and makes install
# fail before the script mutates any service.
printf '<!-- foreign prose mentions agentstart-installer-owned: agentweb.broker.v1 but is not the ownership marker -->\n' >"$broker_plist"
foreign_plan=$(run_check)
printf '%s\n' "$foreign_plan" | grep -F 'agentweb.broker' | grep -F 'REFUSE' >/dev/null \
    || fail "foreign retired broker was not reported"
if HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    "$root/scripts/install-launchagents" --install >/dev/null 2>&1; then
    fail "foreign retired broker was accepted"
fi
grep -Fq '<!-- foreign prose mentions agentstart-installer-owned: agentweb.broker.v1 but is not the ownership marker -->' "$broker_plist" \
    || fail "foreign retired broker plist was changed"
rm -- "$broker_plist"

# Agentbrain is rendered with no conduit environment even when obsolete
# override variables are present in the caller.
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentbrain"
chmod +x "$bin_dir/agentbrain"
HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    AGENTSTART_INSTALL_CONDUIT_SOCKET=/obsolete/socket \
    AGENTSTART_INSTALL_CONDUIT_TOKEN_FILE=/obsolete/token \
    "$root/scripts/install-launchagents" --install >/dev/null
if grep -Fq 'AGENTSCRAPE_CONDUIT' "$launch_agents/agentbrain.worker.plist"; then
    fail "Agentbrain worker still carries retired conduit environment"
fi

printf 'ok\n'
