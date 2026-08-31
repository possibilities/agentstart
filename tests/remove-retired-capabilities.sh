#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-retired-capabilities.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fail() {
    printf 'remove-retired-capabilities test: %s\n' "$*" >&2
    exit 1
}

retired_root="$test_root/capabilities"
resources_root="$test_root/resources"

run_cleanup() {
    AGENTSTART_RETIRED_CAPABILITIES_ROOT="$retired_root" \
        AGENTSTART_RESOURCES_ROOT="$resources_root" \
        "$root/scripts/remove-retired-capabilities" "$@"
}

run_cleanup_with_roots() {
    local selected_retired_root="$1"
    local selected_resources_root="$2"
    shift 2
    AGENTSTART_RETIRED_CAPABILITIES_ROOT="$selected_retired_root" \
        AGENTSTART_RESOURCES_ROOT="$selected_resources_root" \
        "$root/scripts/remove-retired-capabilities" "$@"
}

reset_roots() {
    rm -rf -- "$retired_root" "$resources_root"
    mkdir -p "$resources_root/skills/demo/agents"
    printf '%s\n' 'shared reference' >"$test_root/shared-reference.md"
    printf '%s\n' 'managed skill' >"$resources_root/skills/demo/SKILL.md"
    ln -s "$test_root/shared-reference.md" \
        "$resources_root/skills/demo/MANIFEST.md"
    # shellcheck disable=SC2016 # The manifest contains the literal skill invocation.
    printf '%s\n' \
        'interface:' \
        '  display_name: "Demo"' \
        '  default_prompt: "Use $demo."' \
        '' \
        'policy:' \
        '  allow_implicit_invocation: false' \
        >"$resources_root/skills/demo/agents/openai.yaml"
}

# The original pack manifest remains sufficient proof for the tree it owned.
reset_roots
mkdir -p "$retired_root/packs/common"
printf '%s\n' \
    '{"schema_version":1,"id":"common","default":true}' \
    >"$retired_root/packs/common/capability.json"
printf '%s\n' 'old projection' >"$retired_root/packs/common/projection"
run_cleanup --install >/dev/null
[ ! -e "$retired_root" ] || fail "manifest-owned tree survived cleanup"

# A transition-era residue may have lost the pack manifest. Every remaining
# path must still match the freshly rendered replacement, with only the exact
# later invocation-policy trailer allowed on OpenAI manifests.
reset_roots
mkdir -p "$retired_root/packs/common/skills/demo/agents"
cp "$resources_root/skills/demo/SKILL.md" \
    "$retired_root/packs/common/skills/demo/SKILL.md"
ln -s "$test_root/shared-reference.md" \
    "$retired_root/packs/common/skills/demo/MANIFEST.md"
# shellcheck disable=SC2016 # The manifest contains the literal skill invocation.
printf '%s\n' \
    'interface:' \
    '  display_name: "Demo"' \
    '  default_prompt: "Use $demo."' \
    >"$retired_root/packs/common/skills/demo/agents/openai.yaml"
plan=$(run_cleanup --check)
printf '%s\n' "$plan" | grep -F 'byte-proved managed residue' >/dev/null \
    || fail "check mode did not identify the managed residue"
[ -e "$retired_root" ] || fail "check mode mutated the managed residue"
run_cleanup --install >/dev/null
[ ! -e "$retired_root" ] || fail "managed residue survived cleanup"

# Any changed file, unknown path, or link makes the whole tree foreign and
# leaves every byte in place.
reset_roots
mkdir -p "$retired_root/packs/common/skills/demo"
printf '%s\n' 'independent content' \
    >"$retired_root/packs/common/skills/demo/SKILL.md"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted modified skill content"
fi
[ -e "$retired_root/packs/common/skills/demo/SKILL.md" ] \
    || fail "refused cleanup removed modified content"

reset_roots
mkdir -p "$retired_root/packs/common/skills/demo"
cp "$resources_root/skills/demo/SKILL.md" \
    "$retired_root/packs/common/skills/demo/SKILL.md"
printf '%s\n' 'unknown' >"$retired_root/independent.txt"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted an unknown path"
fi
[ -e "$retired_root/independent.txt" ] \
    || fail "refused cleanup removed the unknown path"

reset_roots
mkdir -p "$retired_root/packs/common/skills/demo"
ln -s "$resources_root/skills/demo/SKILL.md" \
    "$retired_root/packs/common/skills/demo/SKILL.md"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted a linked occupant"
fi
[ -L "$retired_root/packs/common/skills/demo/SKILL.md" ] \
    || fail "refused cleanup removed the linked occupant"

# The one permitted OpenAI-manifest difference is byte-exact. Extra trailing
# newlines are content, and command substitution must not erase them.
reset_roots
mkdir -p "$retired_root/packs/common/skills/demo/agents"
# shellcheck disable=SC2016 # The manifest contains the literal skill invocation.
printf '%s\n' \
    'interface:' \
    '  display_name: "Demo"' \
    '  default_prompt: "Use $demo."' \
    >"$retired_root/packs/common/skills/demo/agents/openai.yaml"
printf '\n\n' >>"$resources_root/skills/demo/agents/openai.yaml"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted extra bytes after the invocation-policy trailer"
fi
[ -e "$retired_root/packs/common/skills/demo/agents/openai.yaml" ] \
    || fail "policy-suffix refusal removed the retired manifest"

# Link targets are byte strings too; a trailing newline is not normalized.
reset_roots
mkdir -p "$retired_root/packs/common/skills/demo"
ln -s "$test_root/shared-reference.md"$'\n' \
    "$retired_root/packs/common/skills/demo/MANIFEST.md"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted link targets that differ by a trailing newline"
fi
[ -L "$retired_root/packs/common/skills/demo/MANIFEST.md" ] \
    || fail "link-target refusal removed the retired link"

# A traversal failure is a refusal, never evidence that the hidden portion is
# empty. The foreign byte must remain even if other managed files were visible.
reset_roots
mkdir -p \
    "$retired_root/packs/common/skills/demo/locked" \
    "$resources_root/skills/demo/locked"
cp "$resources_root/skills/demo/SKILL.md" \
    "$retired_root/packs/common/skills/demo/SKILL.md"
printf '%s\n' 'do not delete' \
    >"$retired_root/packs/common/skills/demo/locked/do-not-delete.txt"
chmod 000 "$retired_root/packs/common/skills/demo/locked"
if run_cleanup --install >/dev/null 2>&1; then
    chmod 700 "$retired_root/packs/common/skills/demo/locked" 2>/dev/null || true
    fail "cleanup accepted an unreadable subtree"
fi
chmod 700 "$retired_root/packs/common/skills/demo/locked"
[ -e "$retired_root/packs/common/skills/demo/locked/do-not-delete.txt" ] \
    || fail "traversal refusal removed hidden foreign content"

# The trusted comparison tree must be canonically disjoint. Otherwise a
# residue can be compared with itself and arbitrary bytes appear managed.
reset_roots
mkdir -p "$retired_root/packs/common/skills"
printf '%s\n' 'do not delete' \
    >"$retired_root/packs/common/skills/do-not-delete.txt"
if run_cleanup_with_roots \
    "$retired_root" "$retired_root/packs/common" --install \
    >/dev/null 2>&1; then
    fail "cleanup accepted a fixed-resource root inside the retired root"
fi
[ -e "$retired_root/packs/common/skills/do-not-delete.txt" ] \
    || fail "overlap refusal removed independent content"

if run_cleanup_with_roots \
    "$retired_root" "$retired_root/packs/../packs/common" --check \
    >/dev/null 2>&1; then
    fail "cleanup accepted a dot-segment alias of an overlapping root"
fi

# APFS firmlinks give the same directory two non-symlink pathnames that
# realpath leaves distinct. Device/inode ancestry must still catch the overlap.
canonical_retired_root=$(/bin/realpath "$retired_root")
firmlink_common="/System/Volumes/Data$canonical_retired_root/packs/common"
if [ -d "$firmlink_common" ] \
    && [ "$(/usr/bin/stat -f '%d:%i' "$retired_root/packs/common")" \
        = "$(/usr/bin/stat -f '%d:%i' "$firmlink_common")" ]; then
    if run_cleanup_with_roots \
        "$retired_root" "$firmlink_common" --check >/dev/null 2>&1; then
        fail "cleanup accepted a firmlink alias of an overlapping root"
    fi
fi

reset_roots
descendant_retired_root="$resources_root/retired"
mkdir -p "$descendant_retired_root/packs/common"
printf '%s\n' \
    '{"schema_version":1,"id":"common","default":true}' \
    >"$descendant_retired_root/packs/common/capability.json"
printf '%s\n' 'do not delete' >"$descendant_retired_root/do-not-delete.txt"
if run_cleanup_with_roots \
    "$descendant_retired_root" "$resources_root" --install \
    >/dev/null 2>&1; then
    fail "cleanup accepted a retired root inside the fixed-resource root"
fi
[ -e "$descendant_retired_root/do-not-delete.txt" ] \
    || fail "reverse-overlap refusal removed independent content"

home_parent=$(/bin/realpath "$HOME/..")
if run_cleanup_with_roots \
    "$home_parent" "$resources_root" --check >/dev/null 2>&1; then
    fail "cleanup accepted a retired root containing the home directory"
fi

# A trailing slash must not hide that the selected root is itself a link.
reset_roots
linked_target="$test_root/linked-retired-target"
linked_root="$test_root/linked-retired-root"
mkdir -p "$linked_target/packs/common"
printf '%s\n' \
    '{"schema_version":1,"id":"common","default":true}' \
    >"$linked_target/packs/common/capability.json"
printf '%s\n' 'do not delete' >"$linked_target/do-not-delete.txt"
ln -s "$linked_target" "$linked_root"
if run_cleanup_with_roots \
    "$linked_root/" "$resources_root" --install >/dev/null 2>&1; then
    fail "cleanup followed a linked retired root with a trailing slash"
fi
[ -e "$linked_target/do-not-delete.txt" ] \
    || fail "linked-root refusal deleted the link target"
[ -L "$linked_root" ] || fail "linked-root refusal removed the link"

# A valid manifest reached through a linked ancestor proves nothing about the
# root that would be recursively removed.
reset_roots
manifest_source="$test_root/foreign-manifest-source"
mkdir -p "$manifest_source/common" "$retired_root"
printf '%s\n' \
    '{"schema_version":1,"id":"common","default":true}' \
    >"$manifest_source/common/capability.json"
ln -s "$manifest_source" "$retired_root/packs"
printf '%s\n' 'independent content' >"$retired_root/do-not-delete.txt"
if run_cleanup --install >/dev/null 2>&1; then
    fail "cleanup accepted a manifest through a linked ancestor"
fi
[ -e "$retired_root/do-not-delete.txt" ] \
    || fail "linked-manifest refusal removed independent content"

# Install-mode refusals quarantine first, then restore the complete tree. No
# private staging directory should remain after an ordinary refusal.
if /usr/bin/find "$test_root" -maxdepth 1 \
    -name '.*.agentstart-cleanup.*' -print | /usr/bin/grep -q .; then
    fail "cleanup left a quarantine directory after restoring a refused tree"
fi

printf 'ok\n'
