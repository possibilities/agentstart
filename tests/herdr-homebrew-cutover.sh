#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
socket_pid=''

cleanup() {
    if [ -n "$socket_pid" ]; then
        kill "$socket_pid" 2>/dev/null || true
        wait "$socket_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
    printf 'herdr-homebrew-cutover test: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    fixture="$test_root/$1"
    home="$fixture/home"
    state="$fixture/state"
    config="$fixture/config/herdr"
    brew_bin="$fixture/brew/herdr"
    legacy_bin="$home/.local/bin/herdr"
    mkdir -p "$state" "$config" "$(dirname -- "$brew_bin")" "$(dirname -- "$legacy_bin")"

    cp "$root/tests/fixtures/herdr-protocol" "$brew_bin"
    cp "$root/tests/fixtures/herdr-protocol" "$legacy_bin"
    chmod 0755 "$brew_bin" "$legacy_bin"
    printf '%040d\n' 0 >"$state/herdr-built-commit"
    printf 'fixture build log\n' >"$state/herdr-build.log"
    touch -r "$state/herdr-built-commit" "$legacy_bin"
}

select_runtime() {
    HOME="$home" \
        AGENTSTART_STATE_ROOT="$state" \
        AGENTSTART_HERDR_CONFIG_ROOT="$config" \
        AGENTSTART_HERDR_ALLOW_CUTOVER="${4:-0}" \
        FAKE_BREW_HERDR_PROTOCOL="$2" \
        FAKE_LEGACY_HERDR_PROTOCOL="$3" \
        "$root/scripts/select-herdr-runtime" "$brew_bin"
}

make_fixture old_formula
selected=$(select_runtime old_formula 20 21)
[ "$selected" = "$legacy_bin" ] || fail "old formula did not retain the compatible client"
[ -f "$legacy_bin" ] || fail "old formula removed the compatible client"
[ -f "$state/herdr-built-commit" ] || fail "old formula removed legacy ownership evidence"

make_fixture live_server
python3 - "$config/herdr.sock" <<'PYTHON' &
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
    [ -S "$config/herdr.sock" ] && break
    sleep 0.01
done
[ -S "$config/herdr.sock" ] || fail "socket fixture did not start"
selected=$(select_runtime live_server 21 21)
[ "$selected" = "$legacy_bin" ] || fail "live server did not defer Homebrew cutover"
[ -f "$legacy_bin" ] || fail "live server lost the compatible client"
kill "$socket_pid"
wait "$socket_pid" 2>/dev/null || true
socket_pid=''

make_fixture successful_cutover
mv "$brew_bin" "$brew_bin.real"
ln -s "${brew_bin##*/}.real" "$brew_bin"
selected=$(select_runtime successful_cutover 21 21 1)
[ "$selected" = "$brew_bin" ] || fail "eligible formula was not selected"
[ ! -e "$legacy_bin" ] || fail "proved legacy binary survived successful cutover"
[ ! -e "$state/herdr-built-commit" ] || fail "proved legacy receipt survived successful cutover"
[ ! -e "$state/herdr-build.log" ] || fail "proved legacy log survived successful cutover"

make_fixture authorization_required
selected=$(select_runtime authorization_required 21 21)
[ "$selected" = "$legacy_bin" ] || fail "ordinary convergence performed the explicit cutover"
[ -f "$legacy_bin" ] || fail "ordinary convergence removed the legacy client"

make_fixture uncertain_socket_root
mv "$config" "$config.real"
ln -s "$config.real" "$config"
selected=$(select_runtime uncertain_socket_root 21 21 1)
[ "$selected" = "$legacy_bin" ] || fail "symlinked socket root did not fail closed"
[ -f "$legacy_bin" ] || fail "uncertain socket audit removed the legacy client"

make_fixture malformed_receipt
printf 'not-a-commit\n' >"$state/herdr-built-commit"
if select_runtime malformed_receipt 21 21 1 >"$fixture/output" 2>"$fixture/error"; then
    fail "malformed receipt was accepted"
fi
[ -f "$legacy_bin" ] || fail "malformed receipt removed its occupant"
[ -f "$state/herdr-built-commit" ] || fail "malformed receipt evidence was removed"

make_fixture symlink_occupant
mv "$legacy_bin" "$legacy_bin.real"
ln -s "$legacy_bin.real" "$legacy_bin"
if select_runtime symlink_occupant 21 21 1 >"$fixture/output" 2>"$fixture/error"; then
    fail "symlink occupant was accepted"
fi
[ -L "$legacy_bin" ] || fail "symlink occupant was removed"

make_fixture mismatched_write_time
touch -t 202001010000 "$legacy_bin"
if select_runtime mismatched_write_time 21 21 1 >"$fixture/output" 2>"$fixture/error"; then
    fail "mismatched write time was accepted"
fi
[ -f "$legacy_bin" ] || fail "mismatched occupant was removed"
[ -f "$state/herdr-built-commit" ] || fail "mismatched ownership evidence was removed"

printf 'herdr Homebrew cutover tests passed\n'
