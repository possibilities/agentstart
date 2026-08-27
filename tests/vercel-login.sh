#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-vercel-login.XXXXXX")
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'vercel-login test: %s\n' "$*" >&2
    exit 1
}

fake_npx="$work/npx"
state="$work/state"
log="$work/log"
cat >"$fake_npx" <<'EOF'
#!/bin/bash
set -u
printf '<%s>' "$@" >>"$AGENTSTART_TEST_VERCEL_LOG"
printf '\n' >>"$AGENTSTART_TEST_VERCEL_LOG"
case "${1:-} ${2:-} ${3:-}" in
    '--yes vercel@59.9.1 whoami')
        if [ -f "$AGENTSTART_TEST_VERCEL_STATE" ]; then
            printf 'possibilities\n'
            exit 0
        fi
        exit 1
        ;;
    '--yes vercel@59.9.1 login')
        printf 'logged-in\n' >"$AGENTSTART_TEST_VERCEL_STATE"
        printf 'device authorization complete\n'
        exit 0
        ;;
esac
exit 2
EOF
chmod +x "$fake_npx"

plan=$("$root/scripts/install-vercel-login" --check)
printf '%s\n' "$plan" \
    | grep -F 'VERCEL_TOKEN_STORAGE=file npx --yes vercel@59.9.1 whoami' >/dev/null \
    || fail "check output does not pin the file-backed Vercel CLI probe"

printf 'logged-in\n' >"$state"
AGENTSTART_NPX_BIN="$fake_npx" \
    AGENTSTART_TEST_VERCEL_STATE="$state" \
    AGENTSTART_TEST_VERCEL_LOG="$log" \
    "$root/scripts/install-vercel-login" --install >/dev/null
[ "$(wc -l <"$log" | tr -d ' ')" -eq 1 ] \
    || fail "an existing login did more than one whoami probe"
grep -Fx '<--yes><vercel@59.9.1><whoami>' "$log" >/dev/null \
    || fail "an existing login did not use the pinned CLI"

rm -f "$state" "$log"
set +e
missing_output=$(
    AGENTSTART_NPX_BIN="$fake_npx" \
        AGENTSTART_TEST_VERCEL_STATE="$state" \
        AGENTSTART_TEST_VERCEL_LOG="$log" \
        "$root/scripts/install-vercel-login" --install 2>&1
)
missing_status=$?
set -e
[ "$missing_status" -ne 0 ] \
    || fail "a missing noninteractive login reported success"
printf '%s\n' "$missing_output" \
    | grep -F 'device authorization needs a terminal' >/dev/null \
    || fail "a missing noninteractive login did not name its terminal requirement"
[ ! -e "$state" ] \
    || fail "a noninteractive install attempted device authorization"

rm -f "$log"
/usr/bin/script -q /dev/null /usr/bin/env \
    AGENTSTART_NPX_BIN="$fake_npx" \
    AGENTSTART_TEST_VERCEL_STATE="$state" \
    AGENTSTART_TEST_VERCEL_LOG="$log" \
    "$root/scripts/install-vercel-login" --install >/dev/null
[ -f "$state" ] \
    || fail "interactive device authorization did not establish a login"
[ "$(wc -l <"$log" | tr -d ' ')" -eq 3 ] \
    || fail "interactive login did not probe, authorize, and verify exactly once"
sed -n '1p' "$log" | grep -Fx '<--yes><vercel@59.9.1><whoami>' >/dev/null \
    || fail "interactive login did not begin with whoami"
sed -n '2p' "$log" | grep -Fx '<--yes><vercel@59.9.1><login>' >/dev/null \
    || fail "interactive login did not run device authorization"
sed -n '3p' "$log" | grep -Fx '<--yes><vercel@59.9.1><whoami>' >/dev/null \
    || fail "interactive login did not verify the result"
