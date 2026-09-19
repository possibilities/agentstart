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
test_voice_checkout="$test_root/agentvoice-checkout"
mkdir -p "$launch_agents" "$bin_dir" "$state_dir"
export AGENTSTART_INSTALL_AGENTVOICE_TEST_CHECKOUT="$test_voice_checkout"
export AGENTSTART_INSTALL_AGENTVOICE_TEST_REVISION=1111111111111111111111111111111111111111

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
printf '%s\n' "$plan" | grep -F "skipped io.arthack.agentlab.serve (no $bin_dir/agentlab)" >/dev/null \
    || fail "missing AgentLab binary was not skipped"
printf '%s\n' "$plan" | grep -F 'io.arthack.agentvoice-test.wait' | grep -F 'not configured; would skip' >/dev/null \
    || fail "unprepared AgentVoice test server was not skipped"
printf '%s\n' "$plan" | grep -F 'io.arthack.agentvoice-test.serve' | grep -F 'not configured; would skip' >/dev/null \
    || fail "unprepared AgentVoice test reader was not skipped"
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
        [ -z "${AGENTSTART_TEST_LAUNCHCTL_LAST_EXIT:-}" ] ||
            printf 'last exit code = %s\n' "$AGENTSTART_TEST_LAUNCHCTL_LAST_EXIT"
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
assert value["ProgramArguments"] == [sys.argv[2], "serve", "--tailscale"]
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

# AgentLab's exact selector renders one resident full-stack service. Status
# additionally proves its public read-only readiness contract.
lab_label=io.arthack.agentlab.serve
lab_plist="$launch_agents/$lab_label.plist"
cat >"$bin_dir/agentlab" <<'EOF'
#!/bin/sh
if [ "${1:-}" = status ] && [ "${AGENTSTART_TEST_AGENTLAB_UNREADY:-0}" = 1 ]; then
    exit 1
fi
exit 0
EOF
chmod +x "$bin_dir/agentlab"
target_plan=$(run_installer --check --service "$lab_label")
printf '%s\n' "$target_plan" | grep -F "$lab_label" | grep -F 'install' >/dev/null \
    || fail "targeted AgentLab plan omitted its absent service"
if printf '%s\n' "$target_plan" | grep -F 'io.arthack.agentvoice.serve' >/dev/null; then
    fail "targeted AgentLab plan included the AgentVoice reader"
fi

: >"$target_launchctl_log"
: >"$target_launchctl_state"
cp "$attention_plist" "$test_root/attention-before-agentlab-targeted.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$lab_label" >/dev/null
/usr/bin/python3 - "$lab_plist" "$bin_dir/agentlab" "$test_home" "$state_dir" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["ProgramArguments"] == [sys.argv[2], "serve"]
assert value["EnvironmentVariables"] == {
    "HOME": sys.argv[3],
    "PATH": value["EnvironmentVariables"]["PATH"],
    "AGENTLAB_FEEDBACK_DB_PATH": sys.argv[3] + "/Library/Application Support/AgentLab/feedback-v1.sqlite3",
}
assert sys.argv[2].rsplit("/", 1)[0] in value["EnvironmentVariables"]["PATH"].split(":")
assert value["KeepAlive"] and value["RunAtLoad"] and value["ProcessType"] == "Standard"
assert value["Umask"] == 63 and value["ThrottleInterval"] == 10
assert value["StandardOutPath"] == value["StandardErrorPath"] == sys.argv[4] + "/agentlab/server.log"
PYTHON
cmp "$attention_plist" "$test_root/attention-before-agentlab-targeted.plist" \
    || fail "targeted AgentLab installation rewrote a neighboring service"
cp "$lab_plist" "$test_root/agentlab-before-repeat.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$lab_label" >/dev/null
cmp "$lab_plist" "$test_root/agentlab-before-repeat.plist" \
    || fail "repeat targeted AgentLab installation changed an identical plist"
[ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 1 ] \
    || fail "repeat targeted AgentLab installation reloaded its healthy service"
[ "$(grep -c '^bootout ' "$target_launchctl_log")" -eq 1 ] \
    || fail "repeat targeted AgentLab installation stopped its healthy service"
target_status=$(
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        run_installer --status --service "$lab_label"
)
printf '%s\n' "$target_status" | grep -F "$lab_label" | grep -F 'state=running' | grep -F 'readiness=ready' >/dev/null \
    || fail "targeted AgentLab status omitted its running ready backend"
target_status=$(
    AGENTSTART_TEST_LAUNCHCTL_LAST_EXIT=143 \
        AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        run_installer --status --service "$lab_label"
)
printf '%s\n' "$target_status" | grep -F "$lab_label" | grep -F 'state=running' | grep -F 'last_exit=143' | grep -F 'readiness=ready' >/dev/null \
    || fail "targeted AgentLab status treated a running ready job's stale prior exit as current failure"
if AGENTSTART_TEST_AGENTLAB_UNREADY=1 \
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --status --service "$lab_label" >/dev/null 2>&1; then
    fail "targeted AgentLab status accepted a failed backend readiness probe"
fi
printf '<!-- independent AgentLab -->\n' >"$lab_plist"
if AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$lab_label" >/dev/null 2>&1; then
    fail "targeted AgentLab installation accepted a foreign ownership marker"
fi
grep -Fxq '<!-- independent AgentLab -->' "$lab_plist" \
    || fail "targeted AgentLab installation overwrote a foreign service"
rm -- "$bin_dir/agentlab" "$lab_plist"

# AgentLab's Codex app-server is a separate daemon and exact selector. Its
# readiness check observes the socket without opening it or attaching a client.
codex_label=io.arthack.agentlab.codex-app-server
codex_plist="$launch_agents/$codex_label.plist"
codex_socket="$test_root/codex.sock"
export AGENTSTART_INSTALL_AGENTLAB_CODEX_SOCKET="$codex_socket"
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/codex"
chmod +x "$bin_dir/codex"
target_plan=$(run_installer --check --service "$codex_label")
printf '%s\n' "$target_plan" | grep -F "$codex_label" | grep -F 'install' >/dev/null \
    || fail "targeted AgentLab Codex daemon plan omitted its absent service"
if printf '%s\n' "$target_plan" | grep -F 'io.arthack.agentvoice.serve' >/dev/null; then
    fail "targeted AgentLab Codex daemon plan included AgentVoice"
fi
: >"$target_launchctl_log"
: >"$target_launchctl_state"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    run_installer --install --service "$codex_label" >/dev/null
/usr/bin/python3 - "$codex_plist" "$bin_dir/codex" "$test_home" "$state_dir" "$codex_socket" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
socket = sys.argv[5]
assert value["Label"] == "io.arthack.agentlab.codex-app-server"
assert value["ProgramArguments"] == [sys.argv[2], "app-server", "--listen", "unix://" + socket]
assert value["EnvironmentVariables"] == {"HOME": sys.argv[3], "PATH": value["EnvironmentVariables"]["PATH"]}
assert value["KeepAlive"] and value["RunAtLoad"] and value["ProcessType"] == "Standard"
assert value["Umask"] == 63 and value["ThrottleInterval"] == 10
assert value["StandardOutPath"] == value["StandardErrorPath"] == sys.argv[4] + "/codex/codex-app-server.log"
PYTHON
if run_installer --status --service "$codex_label" >/dev/null 2>&1; then
    fail "AgentLab Codex daemon readiness accepted a missing socket"
fi
mkdir -p "$(dirname -- "$codex_socket")"
/usr/bin/python3 - "$codex_socket" <<'PYTHON'
import socket
import sys
sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PYTHON
target_status=$(
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        run_installer --status --service "$codex_label"
)
printf '%s\n' "$target_status" | grep -F "$codex_label" | grep -F 'readiness=socket-ready' >/dev/null \
    || fail "AgentLab Codex daemon status omitted socket readiness"
rm -- "$bin_dir/codex" "$codex_plist" "$codex_socket"
unset AGENTSTART_INSTALL_AGENTLAB_CODEX_SOCKET

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
assert value["ProgramArguments"] == [sys.argv[2], "serve", "--tailscale"]
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

# The interim AgentVoice test services remain exact-label neighbors: both pin
# the isolated workspace, only the reader names the non-default origin, and a
# targeted convergence does not touch production or the other test service.
mkdir -p "$test_voice_checkout/src" "$test_voice_checkout/node_modules" \
    "$test_voice_checkout/web/node_modules/.bin"
printf '// isolated fixture entrypoint\n' >"$test_voice_checkout/src/main.ts"
pair_plan=$(run_installer --check --service io.arthack.agentvoice-test.wait)
printf '%s\n' "$pair_plan" | grep -F 'not configured; would skip' >/dev/null \
    || fail "AgentVoice test server activated before reader dependencies were prepared"
printf '#!/bin/sh\nexit 0\n' >"$test_voice_checkout/web/node_modules/.bin/portless"
chmod +x "$test_voice_checkout/web/node_modules/.bin/portless"
mkdir -p "$test_voice_checkout/web/node_modules/vite"
printf '{"name":"vite"}\n' >"$test_voice_checkout/web/node_modules/vite/package.json"
mkdir -p "$test_voice_checkout/node_modules/zod"
printf '{"name":"zod","type":"module","main":"index.js"}\n' \
    >"$test_voice_checkout/node_modules/zod/package.json"
printf 'export const z = {};\n' >"$test_voice_checkout/node_modules/zod/index.js"
mkdir -p "$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server"
cat >"$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/package.json" <<'JSON'
{"name":"@modelcontextprotocol/sdk","type":"module","exports":{"./server/mcp.js":"./server/mcp.js","./server/webStandardStreamableHttp.js":"./server/webStandardStreamableHttp.js"}}
JSON
printf 'export class McpServer {}\n' \
    >"$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server/mcp.js"
printf 'export class WebStandardStreamableHTTPServerTransport {}\n' \
    >"$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js"
guarded_plan=$(run_installer --check)
printf '%s\n' "$guarded_plan" | grep -F 'io.arthack.agentvoice-test.wait' | grep -F 'not configured; would skip' >/dev/null \
    || fail "ordinary full convergence activated the absent AgentVoice test server"
printf '%s\n' "$guarded_plan" | grep -F 'io.arthack.agentvoice-test.serve' | grep -F 'not configured; would skip' >/dev/null \
    || fail "ordinary full convergence activated the absent AgentVoice test reader"
test_voice_workspace="$voice_state_dir/agentvoice/test-workspace"
test_server_label=io.arthack.agentvoice-test.wait
test_reader_label=io.arthack.agentvoice-test.serve
test_server_plist="$launch_agents/$test_server_label.plist"
test_reader_plist="$launch_agents/$test_reader_label.plist"
printf '<!-- production reader sentinel -->\n' >"$voice_plist"
cp "$voice_plist" "$test_root/voice-before-test-targets.plist"

for test_label in "$test_server_label" "$test_reader_label"; do
    target_plan=$(AGENTSTART_TEST_STATE_DIR="$voice_state_dir" run_installer --check --service "$test_label")
    printf '%s\n' "$target_plan" | grep -F "$test_label" | grep -F 'install' >/dev/null \
        || fail "targeted AgentVoice test plan omitted $test_label"
    if printf '%s\n' "$target_plan" | grep -F "$voice_label" >/dev/null; then
        fail "targeted AgentVoice test plan included the production reader"
    fi

    : >"$target_launchctl_log"
    : >"$target_launchctl_state"
    cp "$attention_plist" "$test_root/attention-before-$test_label.plist"
    if [ "$test_label" = "$test_reader_label" ]; then
        cp "$test_server_plist" "$test_root/test-server-before-reader.plist"
    fi
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
        run_installer --install --service "$test_label" >/dev/null
    cmp "$attention_plist" "$test_root/attention-before-$test_label.plist" \
        || fail "targeted AgentVoice test installation rewrote a neighboring service"
    cmp "$voice_plist" "$test_root/voice-before-test-targets.plist" \
        || fail "targeted AgentVoice test installation rewrote the production reader"
    if [ "$test_label" = "$test_server_label" ]; then
        [ ! -e "$test_reader_plist" ] \
            || fail "targeted AgentVoice test-server installation created its sibling reader"
    else
        cmp "$test_server_plist" "$test_root/test-server-before-reader.plist" \
            || fail "targeted AgentVoice test-reader installation rewrote its sibling server"
    fi
    [ -d "$test_voice_workspace" ] \
        || fail "AgentVoice test installation did not prepare its isolated workspace"
    [ "$(grep -c '^bootout ' "$target_launchctl_log")" -eq 1 ] \
        || fail "AgentVoice test convergence did not replace the temporary $test_label job"
    [ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 1 ] \
        || fail "AgentVoice test convergence did not bootstrap $test_label exactly once"
    if grep -v -F "$test_label" "$target_launchctl_log" >/dev/null; then
        fail "targeted AgentVoice test installation called launchctl for a neighboring service"
    fi

    target_status=$(
        AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
            AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
            AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
            AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
            run_installer --status --service "$test_label"
    )
    printf '%s\n' "$target_status" | grep -F "$test_label" | grep -F 'state=running' | grep -F 'pid=73' >/dev/null \
        || fail "targeted AgentVoice test status omitted $test_label"
    if printf '%s\n' "$target_status" | grep -F "$voice_label" >/dev/null; then
        fail "targeted AgentVoice test status included the production reader"
    fi
done

/usr/bin/python3 - "$test_server_plist" "$test_reader_plist" "$(command -v bun)" "$test_home" "$voice_state_dir" "$test_voice_workspace" "$test_voice_checkout" <<'PYTHON'
import os
import plistlib
import shutil
import sys

server_path, reader_path, program, home, state_root, workspace, checkout = sys.argv[1:]
with open(server_path, "rb") as handle:
    server = plistlib.load(handle)
with open(reader_path, "rb") as handle:
    reader = plistlib.load(handle)

entrypoint = checkout + "/src/main.ts"
assert server["ProgramArguments"] == [program, "run", entrypoint, "server", "--workspace", workspace]
assert reader["ProgramArguments"] == [
    program,
    "run",
    entrypoint,
    "serve",
    "--tailscale",
    "--workspace",
    workspace,
    "--name",
    "agentvoice-test",
]
for value, log_name in ((server, "test-server.log"), (reader, "test-reader.log")):
    assert value["WorkingDirectory"] == checkout
    assert value["EnvironmentVariables"] == {
        "AGENTSTART_SOURCE_REVISION": "1111111111111111111111111111111111111111",
        "HOME": home,
        "PATH": value["EnvironmentVariables"]["PATH"],
        "XDG_STATE_HOME": state_root,
    }
    assert program.rsplit("/", 1)[0] in value["EnvironmentVariables"]["PATH"].split(":")
    assert os.path.dirname(shutil.which("node")) in value["EnvironmentVariables"]["PATH"].split(":")
    assert value["KeepAlive"] and value["RunAtLoad"] and value["ProcessType"] == "Standard"
    assert value["Umask"] == 63 and value["ThrottleInterval"] == 10
    assert value["StandardOutPath"] == value["StandardErrorPath"] == state_root + "/agentvoice/" + log_name

assert "agentvoice-test" not in server["ProgramArguments"]
assert "agentvoice.localhost" not in reader["ProgramArguments"]
PYTHON

mv "$test_voice_checkout/node_modules/zod/index.js" \
    "$test_voice_checkout/node_modules/zod/index.js.missing"
if AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$test_server_label" >/dev/null 2>&1; then
    fail "activated AgentVoice test service silently skipped missing dependencies"
fi
mv "$test_voice_checkout/node_modules/zod/index.js.missing" \
    "$test_voice_checkout/node_modules/zod/index.js"

mv "$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server/mcp.js" \
    "$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server/mcp.js.missing"
if AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$test_server_label" >/dev/null 2>&1; then
    fail "activated AgentVoice test service accepted a partial MCP SDK installation"
fi
mv "$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server/mcp.js.missing" \
    "$test_voice_checkout/node_modules/@modelcontextprotocol/sdk/server/mcp.js"

if PATH=/usr/bin:/bin \
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$test_server_label" >/dev/null 2>&1; then
    fail "activated AgentVoice test service silently skipped missing Bun"
fi
if bun_loss_status=$(PATH=/usr/bin:/bin \
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --status --service "$test_server_label" 2>&1); then
    fail "AgentVoice test-server status accepted missing Bun"
fi
printf '%s\n' "$bun_loss_status" | grep -F "$test_server_label" | grep -F 'installed program unavailable' >/dev/null \
    || fail "AgentVoice test-server status did not explain missing Bun"

cp "$test_server_plist" "$test_root/test-server-before-repeat.plist"
export AGENTSTART_INSTALL_AGENTVOICE_TEST_REVISION=2222222222222222222222222222222222222222
if drift_status=$(
    AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
        AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
        AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
        AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
        run_installer --status --service "$test_server_label"
); then
    fail "AgentVoice test-server status accepted a stale source revision"
fi
printf '%s\n' "$drift_status" | grep -F "$test_server_label" | grep -F 'source_revision=stale' >/dev/null \
    || fail "AgentVoice test-server status did not explain stale source revision"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$test_server_label" >/dev/null
if cmp -s "$test_server_plist" "$test_root/test-server-before-repeat.plist"; then
    fail "AgentVoice test-server convergence ignored a committed source change"
fi
[ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 2 ] \
    || fail "AgentVoice test-server source change was not loaded"
[ "$(grep -c '^bootout ' "$target_launchctl_log")" -eq 2 ] \
    || fail "AgentVoice test-server source change did not replace the prior job"

cp "$test_server_plist" "$test_root/test-server-before-repeat.plist"
AGENTSTART_INSTALL_LAUNCHCTL="$target_launchctl" \
    AGENTSTART_TEST_LAUNCHCTL_LOG="$target_launchctl_log" \
    AGENTSTART_TEST_LAUNCHCTL_STATE="$target_launchctl_state" \
    AGENTSTART_TEST_STATE_DIR="$voice_state_dir" \
    run_installer --install --service "$test_server_label" >/dev/null
cmp "$test_server_plist" "$test_root/test-server-before-repeat.plist" \
    || fail "repeat AgentVoice test-server convergence changed an identical plist"
[ "$(grep -c '^bootstrap ' "$target_launchctl_log")" -eq 2 ] \
    || fail "repeat AgentVoice test-server convergence reloaded its healthy service"
[ "$(grep -c '^bootout ' "$target_launchctl_log")" -eq 2 ] \
    || fail "repeat AgentVoice test-server convergence stopped its healthy service"

rm -- "$test_server_plist" "$test_reader_plist" "$voice_plist"
export AGENTSTART_INSTALL_AGENTVOICE_TEST_CHECKOUT="$test_root/missing-agentvoice-checkout"

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
printf '%s\n' "$status_output" | grep -F 'io.arthack.agentvoice-test.wait' | grep -F 'not activated' >/dev/null \
    || fail "status treated an unprepared AgentVoice test server as unhealthy"
printf '%s\n' "$status_output" | grep -F 'io.arthack.agentvoice-test.serve' | grep -F 'not activated' >/dev/null \
    || fail "status treated an unprepared AgentVoice test reader as unhealthy"

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
    environment = plistlib.load(handle)["EnvironmentVariables"]
    actual = environment["AGENTSCRAPE_BROWSER_SESSION"]
assert actual == sys.argv[2], (actual, sys.argv[2])
assert environment["AGENTSCRAPE_OWN_PINNED_SESSION"] == "1"
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
