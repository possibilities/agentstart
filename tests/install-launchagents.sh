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

run_installer() {
    HOME="$test_home" \
        XDG_STATE_HOME="${AGENTSTART_TEST_STATE_DIR:-$state_dir}" \
        AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
        AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
        AGENTSTART_INSTALL_LAUNCHCTL="${AGENTSTART_INSTALL_LAUNCHCTL:-none}" \
        "$root/scripts/install-launchagents" "$@"
}

# The retired web reader is an exact-target cleanup: check is read-only,
# install boots out only the loaded exact-marker-owned job, and no neighboring
# service is sent to launchctl.
chats_label=io.arthack.agentchats.serve
chats_plist="$launch_agents/$chats_label.plist"
printf '<?xml version="1.0"?>\n<!-- agentstart-installer-owned: io.arthack.agentchats.serve.v1 -->\n' >"$chats_plist"
retired_plan=$(run_installer --check --service "$chats_label")
printf '%s\n' "$retired_plan" | grep -F "$chats_label" | grep -F 'would boot out and remove owned plist' >/dev/null \
    || fail "owned retired AgentChats service was not planned for removal"
[ -f "$chats_plist" ] || fail "check mode removed the retired AgentChats plist"

retired_launchctl="$test_root/retired-launchctl"
retired_launchctl_log="$test_root/retired-launchctl.log"
retired_launchctl_state="$test_root/retired-launchctl.loaded"
cat >"$retired_launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$AGENTSTART_TEST_LAUNCHCTL_LOG"
case "$1" in
    print)
        [ "$2" = "gui/$(id -u)/io.arthack.agentchats.serve" ]
        [ -f "$AGENTSTART_TEST_LAUNCHCTL_STATE" ]
        ;;
    bootout)
        [ "$2" = "gui/$(id -u)/io.arthack.agentchats.serve" ]
        rm -f -- "$AGENTSTART_TEST_LAUNCHCTL_STATE"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$retired_launchctl"
: >"$retired_launchctl_state"
AGENTSTART_INSTALL_LAUNCHCTL="$retired_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$retired_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$retired_launchctl_state" \
    run_installer --install --service "$chats_label" >/dev/null
[ ! -e "$chats_plist" ] || fail "owned retired AgentChats plist survived targeted cleanup"
[ ! -e "$retired_launchctl_state" ] || fail "loaded retired AgentChats job was not booted out"
[ "$(grep -c '^bootout ' "$retired_launchctl_log")" -eq 1 ] \
    || fail "retired AgentChats cleanup did not issue exactly one bootout"
if grep -v -F "$chats_label" "$retired_launchctl_log" >/dev/null; then
    fail "retired AgentChats cleanup called launchctl for a neighboring service"
fi

# Mentioning the marker anywhere except the exact second line remains foreign.
printf '<?xml version="1.0"?>\n<!-- foreign service -->\n<!-- agentstart-installer-owned: io.arthack.agentchats.serve.v1 -->\n' >"$chats_plist"
foreign_plan=$(run_installer --check --service "$chats_label")
printf '%s\n' "$foreign_plan" | grep -F "$chats_label" | grep -F 'REFUSE' >/dev/null \
    || fail "foreign retired AgentChats plist was not planned for refusal"
foreign_status=$(run_installer --status --service "$chats_label")
printf '%s\n' "$foreign_status" | grep -F "$chats_label" | grep -F 'ownership=foreign' >/dev/null \
    || fail "retired AgentChats status disagreed with exact-marker cleanup ownership"
if run_installer --install --service "$chats_label" >/dev/null 2>&1; then
    fail "foreign retired AgentChats plist was removed"
fi
grep -Fxq '<!-- foreign service -->' "$chats_plist" \
    || fail "foreign retired AgentChats plist was changed"
rm -- "$chats_plist"

retired_foreign_target="$test_root/foreign-retired-chats.plist"
printf '<?xml version="1.0"?>\n<!-- agentstart-installer-owned: io.arthack.agentchats.serve.v1 -->\n' >"$retired_foreign_target"
ln -s "$retired_foreign_target" "$chats_plist"
if run_installer --install --service "$chats_label" >/dev/null 2>&1; then
    fail "symlinked retired AgentChats plist was removed"
fi
[ -L "$chats_plist" ] && [ "$(readlink "$chats_plist")" = "$retired_foreign_target" ] \
    || fail "symlinked retired AgentChats plist was changed"
grep -Fq 'agentstart-installer-owned: io.arthack.agentchats.serve.v1' "$retired_foreign_target" \
    || fail "symlinked retired AgentChats target was changed"
rm -- "$chats_plist"

plan=$(run_installer --check)
printf '%s\n' "$plan" | grep -F "skipped io.arthack.agenthud.serve (no $bin_dir/agenthud)" >/dev/null \
    || fail "missing AgentHUD binary was not skipped"
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
plan=$(run_installer --check)
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

# A symlink is foreign even when its target has our marker or has disappeared.
foreign_target="$test_root/foreign-attention.plist"
printf '<!-- agentstart-installer-owned: io.arthack.agentattention.serve.v1 -->\n' >"$foreign_target"
cp "$foreign_target" "$test_root/foreign-attention.before"
for link_state in existing dangling; do
    if [ "$link_state" = dangling ]; then rm "$foreign_target"; fi
    ln -s "$foreign_target" "$attention_plist"
    plan=$(run_installer --check)
    printf '%s\n' "$plan" | grep -F 'io.arthack.agentattention.serve' | grep -F 'REFUSE' >/dev/null \
        || fail "$link_state service symlink was not planned for refusal"
    if run_installer --install >/dev/null 2>&1; then
        fail "$link_state service symlink was accepted"
    fi
    [ -L "$attention_plist" ] && [ "$(readlink "$attention_plist")" = "$foreign_target" ] \
        || fail "$link_state service symlink was replaced or redirected"
    if [ "$link_state" = existing ]; then
        cmp "$test_root/foreign-attention.before" "$foreign_target" \
            || fail "foreign service symlink target was changed"
    else
        [ ! -e "$foreign_target" ] || fail "dangling service symlink target was created"
    fi
    rm "$attention_plist"
done

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

# AgentHUD follows the same resident editable-reader frame, and its exact
# selector is the deployment path that must not converge or restart neighbors.
hud_label=io.arthack.agenthud.serve
hud_plist="$launch_agents/$hud_label.plist"
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agenthud"
chmod +x "$bin_dir/agenthud"
target_plan=$(run_installer --check --service "$hud_label")
printf '%s\n' "$target_plan" | grep -F "$hud_label" | grep -F 'install' >/dev/null \
    || fail "targeted HUD plan omitted its absent service"
if printf '%s\n' "$target_plan" | grep -F 'io.arthack.agentattention.serve' >/dev/null; then
    fail "targeted HUD plan included a neighboring service"
fi
if run_installer --check --service io.arthack.unknown.serve >/dev/null 2>&1; then
    fail "targeted convergence accepted an unknown service label"
fi
if run_installer --check --service >/dev/null 2>&1; then
    fail "targeted convergence accepted a missing service label"
fi

target_launchctl="$test_root/target-launchctl"
target_launchctl_log="$test_root/target-launchctl.log"
target_launchctl_state="$test_root/target-launchctl.loaded"
cat >"$target_launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$AGENTSTART_TEST_LAUNCHCTL_LOG"
case "$1" in
    print)
        [ -f "$AGENTSTART_TEST_LAUNCHCTL_STATE" ] || exit 1
        printf 'state = running\npid = 73\n'
        ;;
    bootstrap)
        : >"$AGENTSTART_TEST_LAUNCHCTL_STATE"
        ;;
    bootout)
        rm -f -- "$AGENTSTART_TEST_LAUNCHCTL_STATE"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$target_launchctl"
cp "$attention_plist" "$test_root/attention-before-targeted.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$hud_label" >/dev/null
/usr/bin/python3 - "$hud_plist" "$bin_dir/agenthud" "$test_home" "$state_dir" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["ProgramArguments"] == [sys.argv[2], "serve"]
assert value["EnvironmentVariables"]["HOME"] == sys.argv[3]
assert sys.argv[2].rsplit("/", 1)[0] in value["EnvironmentVariables"]["PATH"].split(":")
assert value["KeepAlive"] and value["RunAtLoad"] and value["ProcessType"] == "Standard"
assert value["Umask"] == 63 and value["ThrottleInterval"] == 10
assert value["StandardOutPath"] == value["StandardErrorPath"] == sys.argv[4] + "/agenthud/server.log"
PYTHON
cmp "$attention_plist" "$test_root/attention-before-targeted.plist" \
    || fail "targeted HUD installation rewrote a neighboring service"
cp "$hud_plist" "$test_root/hud-before-repeat.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$hud_label" >/dev/null
cmp "$hud_plist" "$test_root/hud-before-repeat.plist" \
    || fail "repeat targeted HUD installation changed an identical plist"
[ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 1 ] \
    || fail "repeat targeted HUD installation reloaded its healthy unchanged service"
if grep -q '^bootout ' "$target_launchctl_log"; then
    fail "repeat targeted HUD installation stopped its healthy unchanged service"
fi
if grep -v -F "$hud_label" "$target_launchctl_log" >/dev/null; then
    fail "targeted HUD installation called launchctl for a neighboring service"
fi
target_status=$(
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        run_installer --status --service "$hud_label"
)
printf '%s\n' "$target_status" | grep -F "$hud_label" | grep -F 'state=running' | grep -F 'pid=73' >/dev/null \
    || fail "targeted HUD status omitted its healthy job"
if printf '%s\n' "$target_status" | grep -F 'io.arthack.agentattention.serve' >/dev/null; then
    fail "targeted HUD status included a neighboring service"
fi
printf '<!-- independent HUD -->\n' >"$hud_plist"
if AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$hud_label" >/dev/null 2>&1; then
    fail "targeted HUD installation accepted a foreign ownership marker"
fi
grep -Fxq '<!-- independent HUD -->' "$hud_plist" \
    || fail "targeted HUD installation overwrote a foreign service"
rm -- "$bin_dir/agenthud" "$hud_plist"

# The AgentVoice reader uses the same exact-label frame independently of the
# AgentVoice-owned waiting server. Its first canonical convergence replaces the
# known temporary submitted reader at this label, then becomes restart-free.
voice_label=io.arthack.agentvoice.serve
voice_plist="$launch_agents/$voice_label.plist"
voice_state_dir="$test_root/voice-state"
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentvoice"
chmod +x "$bin_dir/agentvoice"
target_plan=$(run_installer --check --service "$voice_label")
printf '%s\n' "$target_plan" | grep -F "$voice_label" | grep -F 'install' >/dev/null \
    || fail "targeted AgentVoice reader plan omitted its absent service"
if printf '%s\n' "$target_plan" | grep -F "$hud_label" >/dev/null; then
    fail "targeted AgentVoice reader plan included the HUD service"
fi

: >"$target_launchctl_log"
: >"$target_launchctl_state"
cp "$attention_plist" "$test_root/attention-before-voice-targeted.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$voice_label" >/dev/null
/usr/bin/python3 - "$voice_plist" "$bin_dir/agentvoice" "$test_home" "$voice_state_dir" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["ProgramArguments"] == [sys.argv[2], "serve"]
assert value["EnvironmentVariables"]["HOME"] == sys.argv[3]
assert sys.argv[2].rsplit("/", 1)[0] in value["EnvironmentVariables"]["PATH"].split(":")
assert value["EnvironmentVariables"]["XDG_STATE_HOME"] == sys.argv[4]
assert value["KeepAlive"] and value["RunAtLoad"] and value["ProcessType"] == "Standard"
assert value["Umask"] == 63 and value["ThrottleInterval"] == 10
assert value["StandardOutPath"] == value["StandardErrorPath"] == sys.argv[4] + "/agentvoice/server.log"
PYTHON
cmp "$attention_plist" "$test_root/attention-before-voice-targeted.plist" \
    || fail "targeted AgentVoice reader installation rewrote a neighboring service"
[ "$(grep -c '^bootout ' "$target_launchctl_log")" -eq 1 ] \
    || fail "canonical reader convergence did not replace the temporary submitted job"
[ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 1 ] \
    || fail "canonical reader convergence did not bootstrap exactly once"
if grep -v -F "$voice_label" "$target_launchctl_log" >/dev/null; then
    fail "targeted AgentVoice reader installation called launchctl for a neighboring service"
fi

cp "$voice_plist" "$test_root/voice-before-repeat.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$voice_label" >/dev/null
cmp "$voice_plist" "$test_root/voice-before-repeat.plist" \
    || fail "repeat targeted AgentVoice reader installation changed an identical plist"
[ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 1 ] \
    || fail "repeat targeted AgentVoice reader installation reloaded its healthy service"
[ "$(grep -c '^bootout ' "$target_launchctl_log")" -eq 1 ] \
    || fail "repeat targeted AgentVoice reader installation stopped its healthy service"
target_status=$(
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
        run_installer --status --service "$voice_label"
)
printf '%s\n' "$target_status" | grep -F "$voice_label" | grep -F 'state=running' | grep -F 'pid=73' >/dev/null \
    || fail "targeted AgentVoice reader status omitted its healthy job"
if printf '%s\n' "$target_status" | grep -F "$hud_label" >/dev/null; then
    fail "targeted AgentVoice reader status included the HUD service"
fi
printf '<?xml version="1.0"?>\n<!-- foreign AgentVoice reader -->\n<!-- agentstart-installer-owned: io.arthack.agentvoice.serve.v1 -->\n' >"$voice_plist"
if AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$voice_label" >/dev/null 2>&1; then
    fail "targeted AgentVoice reader installation accepted a foreign ownership marker"
fi
grep -Fxq '<!-- foreign AgentVoice reader -->' "$voice_plist" \
    || fail "targeted AgentVoice reader installation overwrote a foreign service"
rm -- "$bin_dir/agentvoice" "$voice_plist"

# With no configured XDG root, the managed reader receives AgentVoice's
# documented default explicitly rather than inheriting launchd's environment.
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/agentvoice"
chmod +x "$bin_dir/agentvoice"
env -u XDG_STATE_HOME \
    HOME="$test_home" \
    AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents" \
    AGENTSTART_INSTALL_BIN_DIR="$bin_dir" \
    AGENTSTART_INSTALL_LAUNCHCTL=none \
    "$root/scripts/install-launchagents" --install --service "$voice_label" >/dev/null
/usr/bin/python3 - "$voice_plist" "$state_dir" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["EnvironmentVariables"]["XDG_STATE_HOME"] == sys.argv[2]
PYTHON
rm -- "$bin_dir/agentvoice" "$voice_plist"

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
