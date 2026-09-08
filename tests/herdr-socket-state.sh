#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-herdr-sockets.XXXXXX")
socket_pid=''
trap 'if [ -n "$socket_pid" ]; then kill "$socket_pid" 2>/dev/null || true; wait "$socket_pid" 2>/dev/null || true; fi; rm -rf -- "$fixture"' EXIT

fail() {
    printf 'herdr-socket-state test: %s\n' "$*" >&2
    exit 1
}

state() {
    HOME="$fixture/home" AGENTSTART_HERDR_CONFIG_ROOT="$fixture/config" \
        "$root/scripts/herdr-socket-state"
}

[ "$(state)" = inactive ] || fail "an absent config root was not inactive"
mkdir -p "$fixture/config/sessions/quiet"
[ "$(state)" = inactive ] || fail "an empty named-session tree was not inactive"

/usr/bin/python3 - "$fixture/config/sessions/quiet/herdr.sock" <<'PYTHON' &
import socket
import sys
import time

server = socket.socket(socket.AF_UNIX)
server.bind(sys.argv[1])
server.listen(1)
time.sleep(30)
PYTHON
socket_pid=$!
for _ in $(seq 1 100); do
    [ -S "$fixture/config/sessions/quiet/herdr.sock" ] && break
    sleep 0.01
done
[ -S "$fixture/config/sessions/quiet/herdr.sock" ] || fail "socket fixture did not start"
[ "$(state)" = present ] || fail "a named server socket was not detected"
kill "$socket_pid"
wait "$socket_pid" 2>/dev/null || true
socket_pid=''
rm "$fixture/config/sessions/quiet/herdr.sock"

printf 'not a socket\n' >"$fixture/config/herdr.sock"
[ "$(state)" = uncertain ] || fail "an unexpected socket-path occupant was not uncertain"
rm "$fixture/config/herdr.sock"

mv "$fixture/config" "$fixture/config.real"
ln -s "$fixture/config.real" "$fixture/config"
[ "$(state)" = uncertain ] || fail "a linked config root was not uncertain"

printf 'ok\n'
