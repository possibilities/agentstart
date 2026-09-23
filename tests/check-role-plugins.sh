#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
resources="$fixture/resources"
mkdir -p "$resources/roles/default"

mock="$fixture/agentroles"
log="$fixture/calls"
cat >"$mock" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = --help ]; then
    printf 'agentroles install --check <role>\n'
    exit 0
fi
printf '%s\n' "$*" >>"$AGENTSTART_TEST_ROLE_CHECK_LOG"
role=${3##*/}
printf '{"schema_version":1,"role":"%s","installed":true,"fresh":false}\n' "$role"
exit 1
EOF
chmod +x "$mock"

set +e
output=$(AGENTSTART_RESOURCES_ROOT="$resources" \
    AGENTSTART_AGENTROLES_BIN="$mock" \
    AGENTSTART_TEST_ROLE_CHECK_LOG="$log" \
    "$root/scripts/check-role-plugins")
status=$?
set -e
[ "$status" -eq 1 ]
[ "$(wc -l <"$log" | tr -d ' ')" -eq 1 ]
grep -Fx "install --check $resources/roles/default" "$log" >/dev/null
printf '%s\n' "$output" | grep -F '"role":"default"' >/dev/null

code_root="$fixture/code"
mkdir -p "$code_root"
set +e
AGENTSTART_CODE_ROOT="$code_root" \
    AGENTSTART_RESOURCES_ROOT="$resources" \
    AGENTSTART_AGENTROLES_BIN="$mock" \
    AGENTSTART_TEST_ROLE_CHECK_LOG="$log" \
    "$root/scripts/sync-skills" --check >/dev/null
status=$?
set -e
[ "$status" -eq 1 ]
[ "$(wc -l <"$log" | tr -d ' ')" -eq 2 ]

rm -rf "$resources/roles"
AGENTSTART_RESOURCES_ROOT="$resources" \
    AGENTSTART_AGENTROLES_BIN="$mock" \
    AGENTSTART_TEST_ROLE_CHECK_LOG="$log" \
    "$root/scripts/check-role-plugins" >/dev/null 2>&1
[ "$(wc -l <"$log" | tr -d ' ')" -eq 2 ]
