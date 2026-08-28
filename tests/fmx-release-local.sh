#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-fmx-release-test.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

fail() {
    printf 'fmx-release-local test: %s\n' "$*" >&2
    exit 1
}

for platform in linux-x86_64 linux-aarch64 macos-x86_64 macos-aarch64; do
    for extension in tar.xz tar.gz; do
        archive="fmx-$platform.$extension"
        printf '%s\n' "$archive" > "$fixture/$archive"
        digest=$(shasum -a 256 "$fixture/$archive" | awk '{print $1}')
        printf '%s  %s\n' "$digest" "$archive" > "$fixture/$archive.sha256"
    done
done

"$root/scripts/fmx-release-local" verify --output "$fixture" \
    | grep -F 'Verified Fmx release set' >/dev/null \
    || fail "the complete fixture did not verify"

printf 'extra\n' > "$fixture/unrelated"
set +e
extra_output=$("$root/scripts/fmx-release-local" verify --output "$fixture" 2>&1)
extra_status=$?
set -e
[ "$extra_status" -ne 0 ] || fail "an extra release file was accepted"
printf '%s\n' "$extra_output" | grep -F 'expected exactly 16' >/dev/null \
    || fail "the extra-file refusal was not diagnostic"

"$root/scripts/fmx-release-local" --help \
    | grep -F 'Build both macOS release jobs serially' >/dev/null \
    || fail "help does not describe serialization"

grep -F 'trap cleanup EXIT' "$root/scripts/fmx-release-local" >/dev/null \
    || fail "the publisher does not clean short-lived credentials on failure"
grep -F 'refusing to clean unexpected path' "$root/scripts/fmx-release-local" >/dev/null \
    || fail "temporary cleanup is not path-guarded"
grep -F 'rev-parse refs/remotes/origin/main' "$root/scripts/fmx-release-local" >/dev/null \
    || fail "publication does not pin the release to origin/main"

printf 'fmx-release-local tests passed\n'
