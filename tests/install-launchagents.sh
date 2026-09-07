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
[ ! -e "$launch_agents/io.arthack.agentattention.serve.plist" ] \
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
    AGENTSTART_INSTALL_SHARE_HOST=none \
    AGENTSTART_INSTALL_CONDUIT_SOCKET=/obsolete/socket \
    AGENTSTART_INSTALL_CONDUIT_TOKEN_FILE=/obsolete/token \
    "$root/scripts/install-launchagents" --install >/dev/null
if grep -Fq 'AGENTSCRAPE_CONDUIT' "$launch_agents/io.arthack.agentbrain.work.plist"; then
    fail "Agentbrain worker still carries retired conduit environment"
fi

# Status is owner-provided and read-only. It reports lifecycle state and log
# bytes from one launchctl read per installed service, while a deliberately
# unconfigured share ingress remains optional rather than unhealthy.
status_launchctl="$test_root/status-launchctl"
cat >"$status_launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$1" = print ] || exit 1
case "$2" in
    */io.arthack.agentbrain.work | */io.arthack.agentattention.serve)
        printf 'state = running\npid = 42\n'
        ;;
    */io.arthack.agentbrain.doctor)
        printf 'state = waiting\nlast exit code = 0\n'
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$status_launchctl"
status_output=$(HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL="$status_launchctl" \
    "$root/scripts/install-launchagents" --status)
printf '%s\n' "$status_output" | grep -F 'io.arthack.agentbrain.work' | grep -F 'state=running' | grep -F 'log_bytes=0' >/dev/null \
    || fail "status omitted the running Agentbrain worker or its log size"
printf '%s\n' "$status_output" | grep -F 'io.arthack.agentbrain.doctor' | grep -F 'state=waiting' | grep -F 'last_exit=0' >/dev/null \
    || fail "status omitted the healthy periodic doctor"
printf '%s\n' "$status_output" | grep -F 'io.arthack.agentbrain.share' | grep -F 'optional' >/dev/null \
    || fail "status treated an unconfigured share ingress as unhealthy"

install_brain_session() {
    HOME="$test_home" \
        XDG_STATE_HOME="$state_dir" \
        AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
        AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
        AGENTSTART_INSTALL_LAUNCHCTL=none \
        "$root/scripts/install-launchagents" --install
}

assert_brain_session() {
    /usr/bin/python3 - "$launch_agents/io.arthack.agentbrain.work.plist" "$1" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    actual = plistlib.load(handle)["EnvironmentVariables"]["AGENTSCRAPE_BROWSER_SESSION"]
assert actual == sys.argv[2], (actual, sys.argv[2])
PYTHON
}

AGENTSTART_INSTALL_AGENTBRAIN_BROWSER_SESSION=brain-auth install_brain_session >/dev/null
assert_brain_session brain-auth
unset AGENTSTART_INSTALL_AGENTBRAIN_BROWSER_SESSION
install_brain_session >/dev/null
assert_brain_session brain-auth
cp "$launch_agents/io.arthack.agentbrain.work.plist" "$test_root/worker-before.plist"
for invalid_session in '-bad' 'bad session' 'bad/session' "$(printf '%0129d' 0)"; do
    if AGENTSTART_INSTALL_AGENTBRAIN_BROWSER_SESSION="$invalid_session" install_brain_session >/dev/null 2>&1; then
        fail "invalid browser session was accepted"
    fi
    cmp "$test_root/worker-before.plist" "$launch_agents/io.arthack.agentbrain.work.plist" \
        || fail "invalid browser session replaced the installed Worker"
done

# If the browser-session feature was installed immediately before the label
# migration, the new service keeps its pin from that exact predecessor.
sed \
    -e 's/agentstart-installer-owned: io\.arthack\.agentbrain\.work\.v1/agentstart-installer-owned: agentbrain.worker.v1/' \
    -e 's#<string>io\.arthack\.agentbrain\.work</string>#<string>agentbrain.worker</string>#' \
    "$launch_agents/io.arthack.agentbrain.work.plist" \
    >"$launch_agents/agentbrain.worker.plist"
rm "$launch_agents/io.arthack.agentbrain.work.plist"
install_brain_session >/dev/null
assert_brain_session brain-auth
rm "$launch_agents/agentbrain.worker.plist"

AGENTSTART_INSTALL_AGENTBRAIN_BROWSER_SESSION='' install_brain_session >/dev/null
assert_brain_session ''

printf 'ok\n'
