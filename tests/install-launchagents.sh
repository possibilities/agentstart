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

run_check() {
    HOME="$test_home" \
        XDG_STATE_HOME="$state_dir" \
        AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
        AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
        AGENTSTART_INSTALL_LAUNCHCTL=none \
        "$root/scripts/install-launchagents" --check
}

plan=$(run_check)
printf '%s\n' "$plan" | grep -F 'io.arthack.agentattention.serve' | grep -F 'install' >/dev/null \
    || fail "absent current Agentattention service was not planned for install"
HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    "$root/scripts/install-launchagents" --install >/dev/null
attention_plist="$launch_agents/io.arthack.agentattention.serve.plist"
grep -Fq 'agentstart-installer-owned: io.arthack.agentattention.serve.v1' "$attention_plist" \
    || fail "current service lacks its exact ownership marker"
plan=$(run_check)
printf '%s\n' "$plan" | grep -F 'io.arthack.agentattention.serve' | grep -F 'converge' >/dev/null \
    || fail "owned current service was not planned for convergence"

printf '<!-- independent service -->\n' >"$attention_plist"
if HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    "$root/scripts/install-launchagents" --install >/dev/null 2>&1; then
    fail "independent current service was accepted"
fi
grep -Fxq '<!-- independent service -->' "$attention_plist" \
    || fail "independent current service was overwritten"
rm "$attention_plist"
HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    "$root/scripts/install-launchagents" --install >/dev/null

# The owned observer renders the supported daemon command.
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentusage"
chmod +x "$bin_dir/agentusage"
HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    "$root/scripts/install-launchagents" --install >/dev/null
/usr/bin/python3 - "$launch_agents/io.arthack.agentusage.observe.plist" "$bin_dir/agentusage" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["ProgramArguments"] == [sys.argv[2], "daemon", "run"]
PYTHON
rm -- "$bin_dir/agentusage" "$launch_agents/io.arthack.agentusage.observe.plist"

# Install Agentbrain for the status and session-persistence checks below.
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentbrain"
chmod +x "$bin_dir/agentbrain"
HOME="$test_home" \
    XDG_STATE_HOME="$state_dir" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    AGENTSTART_INSTALL_SHARE_HOST=none \
    "$root/scripts/install-launchagents" --install >/dev/null

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

AGENTSTART_INSTALL_AGENTBRAIN_BROWSER_SESSION='' install_brain_session >/dev/null
assert_brain_session ''

# The config watcher uses the same manifest/render/lifecycle owner and pins
# state consistently with one-shot invocations, including non-default XDG.
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentstart"
chmod +x "$bin_dir/agentstart"
install_brain_session >/dev/null
watcher_plist="$launch_agents/io.arthack.agentstart.watch-config.plist"
/usr/bin/python3 - "$watcher_plist" "$bin_dir" "$state_dir" <<'PYTHON'
import os, plistlib, sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["ProgramArguments"] == [sys.argv[2] + "/agentstart", "config", "watch", "--notify"]
assert value["EnvironmentVariables"]["XDG_STATE_HOME"] == sys.argv[3]
assert value["KeepAlive"] and value["RunAtLoad"] and value["Umask"] == 63
assert os.stat(sys.argv[1]).st_mode & 0o777 == 0o600
PYTHON
printf '<!-- independent watcher -->\n' >"$watcher_plist"
if install_brain_session >/dev/null 2>&1; then
    fail "independent config watcher was accepted"
fi
grep -Fxq '<!-- independent watcher -->' "$watcher_plist" \
    || fail "independent watcher was overwritten"

printf 'ok\n'
