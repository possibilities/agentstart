#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-retired-agentweb.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fail() {
    printf 'remove-retired-agentweb test: %s\n' "$*" >&2
    exit 1
}

bin_dir="$test_root/bin"
state_dir="$test_root/state"
mkdir -p "$bin_dir" "$state_dir"

run_cleanup() {
    AGENTSTART_RETIRED_AGENTWEB_BIN_DIR="$bin_dir" \
        AGENTSTART_RETIRED_AGENTWEB_STATE_DIR="$state_dir" \
        "$root/scripts/remove-retired-agentweb" "$@"
}

write_owned() {
    local name
    for name in agentweb agentwebd; do
        printf '#!/bin/bash\n# agentweb-installer-owned:v1\n' >"$bin_dir/$name"
    done
    printf 'agentweb-installer-owned:v1\nroot=/retired\n' >"$state_dir/install-receipt"
}

write_owned
config_file="$test_root/config/agentweb/config.json"
mkdir -p "$(dirname -- "$config_file")"
printf '{}\n' >"$config_file"
printf 'retain private history\n' >"$state_dir/database.sqlite"
printf 'retain audit history\n' >"$state_dir/audit.jsonl"
printf 'retain broker log\n' >"$state_dir/broker.log"
mkdir -p "$state_dir/vault" "$state_dir/keys" "$state_dir/logs"

plan=$(run_cleanup --check)
printf '%s\n' "$plan" | grep -F "$bin_dir/agentweb" | grep -F owned >/dev/null \
    || fail "check mode did not identify the owned command wrapper"
for retained in "$bin_dir/agentweb" "$bin_dir/agentwebd" "$state_dir/install-receipt"; do
    [ -e "$retained" ] || fail "check mode mutated an owned artifact: $retained"
done

run_cleanup --install >/dev/null
for removed in "$bin_dir/agentweb" "$bin_dir/agentwebd" "$state_dir/install-receipt"; do
    [ ! -e "$removed" ] || fail "owned artifact survived cleanup: $removed"
done
for retained in "$config_file" "$state_dir/database.sqlite" "$state_dir/audit.jsonl" \
    "$state_dir/broker.log" "$state_dir/vault" "$state_dir/keys" "$state_dir/logs"; do
    [ -e "$retained" ] || fail "private state was removed: $retained"
done

# Foreign occupants fail the install preflight before any owned neighbor is
# deleted. Check mode reports the refusal but remains a non-mutating plan.
write_owned
printf '#!/bin/bash\n# foreign-owner\n' >"$bin_dir/agentwebd"
foreign_plan=$(run_cleanup --check)
printf '%s\n' "$foreign_plan" | grep -F "$bin_dir/agentwebd" | grep -F foreign >/dev/null \
    || fail "check mode did not report the foreign wrapper"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted a foreign command wrapper"
fi
for retained in "$bin_dir/agentweb" "$bin_dir/agentwebd" "$state_dir/install-receipt"; do
    [ -e "$retained" ] || fail "foreign preflight allowed partial cleanup: $retained"
done

printf 'ok\n'
