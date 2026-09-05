#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

fail() {
    printf 'validate: %s\n' "$*" >&2
    exit 1
}

shell_files="
scripts/install.sh
scripts/sync-skills
scripts/run-skills-cli
scripts/render-capabilities
scripts/sync-codex-skill-policy
scripts/install-agent-clis
scripts/install-agentlaunch-shims
scripts/remove-retired-integrations
scripts/remove-retired-pi
scripts/remove-retired-agentweb
scripts/remove-retired-capabilities
scripts/install-launchagents
scripts/configure-agentsource-webhooks
scripts/agentbrowse-config
scripts/agent-browser-config
scripts/agent-browser-link.sh
scripts/smolmux-config
scripts/agentmux-config
scripts/herdr-config
scripts/select-herdr-runtime
tests/validate.sh
tests/agentbrowse-config.sh
tests/agent-browser-config.sh
tests/agent-browser-link.sh
tests/smolmux-config.sh
tests/agentmux-config.sh
tests/herdr-config.sh
tests/herdr-homebrew-cutover.sh
tests/agentsource-webhooks.sh
tests/install-launchagents.sh
tests/remove-retired-agentweb.sh
tests/remove-retired-capabilities.sh
tests/fixtures/npx
tests/fixtures/herdr-protocol
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

for script in scripts/install.sh scripts/sync-skills scripts/install-agent-clis \
    scripts/run-skills-cli \
    scripts/install-agentlaunch-shims scripts/render-capabilities scripts/install-launchagents \
    scripts/configure-agentsource-webhooks \
    scripts/sync-codex-skill-policy \
    scripts/render-skill-invocation-policy \
    scripts/remove-retired-integrations \
    scripts/remove-retired-pi \
    scripts/remove-retired-agentweb \
    scripts/remove-retired-capabilities \
    scripts/agentbrowse-config scripts/agent-browser-config scripts/smolmux-config scripts/agentmux-config scripts/herdr-config \
    scripts/select-herdr-runtime; do
    [ -x "$script" ] || fail "installer script is not executable: $script"
done
[ -x tests/agentbrowse-config.sh ] \
    || fail "agentbrowse config test is not executable: tests/agentbrowse-config.sh"
[ -x tests/agent-browser-config.sh ] \
    || fail "agent-browser config test is not executable: tests/agent-browser-config.sh"
[ -x tests/agent-browser-link.sh ] \
    || fail "agent-browser link test is not executable: tests/agent-browser-link.sh"
[ -x tests/smolmux-config.sh ] \
    || fail "smolmux config test is not executable: tests/smolmux-config.sh"
[ -x tests/agentmux-config.sh ] \
    || fail "agentmux instance config test is not executable: tests/agentmux-config.sh"
[ -x tests/herdr-config.sh ] \
    || fail "Herdr config test is not executable: tests/herdr-config.sh"
[ -x tests/herdr-homebrew-cutover.sh ] \
    || fail "Herdr Homebrew cutover test is not executable: tests/herdr-homebrew-cutover.sh"
[ -x tests/agentsource-webhooks.sh ] \
    || fail "Agentsource webhook test is not executable: tests/agentsource-webhooks.sh"
[ -x tests/install-launchagents.sh ] \
    || fail "launch agent installer test is not executable: tests/install-launchagents.sh"
[ -x tests/remove-retired-agentweb.sh ] \
    || fail "retired Agentweb cleanup test is not executable: tests/remove-retired-agentweb.sh"
[ -x tests/remove-retired-capabilities.sh ] \
    || fail "retired capability cleanup test is not executable: tests/remove-retired-capabilities.sh"
[ -x config/terminal-control/termctrl ] \
    || fail "Terminal Control shim is missing or not executable"
/usr/bin/python3 -c \
    'import pathlib; compile(pathlib.Path("config/terminal-control/termctrl").read_text(), "config/terminal-control/termctrl", "exec")'

[ -s config/agentbrowse/config.json ] \
    || fail "default agentbrowse config is missing or empty"
/usr/bin/jq -e '
    .version == 2 and
    (.backends | map(.id)) == ["artbird", "apple-container-local"] and
    .backends[0].video == {"fps": 60, "targetBitrateBps": 4792320, "keyframeMaxDistance": 60} and
    (.backends[1] | has("video") | not) and
    .backends[1].maxTargets == 1 and
    .backends[1].accessMode == "loopback" and
    .backends[1].cpus == 2 and
    .backends[1].memory == "6G" and
    .images.defaultImage == "docker.io/onkernel/chromium-headful@sha256:da9ee68cb9d2de0b3c26885ff3bdcf04c944254a36eb127219028ac017ff56f3" and
    .browser.video == {
        "screenRefreshRate": 60,
        "fps": 30,
        "cpuUsed": 4,
        "threads": 4,
        "targetBitrateBps": 2396160,
        "keyframeMaxDistance": 30
    }
' config/agentbrowse/config.json >/dev/null \
    || fail "default agentbrowse config does not declare the locked ordered fallback and Live View capture policy"
tests/agentbrowse-config.sh

[ -s config/agent-browser/config.json ] \
    || fail "default agent-browser config is missing or empty"
/usr/bin/jq -e '
    .provider == "agentbrowse" and
    (.plugins == [{
        "name": "agentbrowse",
        "command": "/bin/sh",
        "args": ["-c", "exec \"$HOME/.local/bin/agentbrowse\" provider"],
        "capabilities": ["browser.provider"]
    }])
' config/agent-browser/config.json >/dev/null \
    || fail "default agent-browser config does not select the agentbrowse provider"
tests/agent-browser-config.sh
tests/agent-browser-link.sh
tests/agentsource-webhooks.sh
tests/install-launchagents.sh
tests/remove-retired-agentweb.sh
tests/remove-retired-capabilities.sh
[ -x scripts/remove-retired-json-hooks.ts ] \
    || fail "retired JSON hook cleanup helper is not executable"
[ ! -e skills/supervise ] \
    || fail "the retired supervise skill returned"
[ ! -e skills/livekit-simulations ] \
    || fail "the retired LiveKit skill returned"
sed -n '/^retired_skill_names=(/,/^)/p' scripts/sync-skills \
    | grep -Fx '    supervise' >/dev/null \
    || fail "the additive skill sync can restore retired supervise copies"
sed -n '/^retired_skill_names=(/,/^)/p' scripts/sync-skills \
    | grep -Fx '    livekit-simulations' >/dev/null \
    || fail "the additive skill sync can restore the retired LiveKit skill"
if grep -q 'temporarily_suppressed_skill_names' scripts/sync-skills; then
    fail "the skill sync still suppresses a published skill"
fi

# The obsolete llm model records stay gone, and the retired Orca overlay must
# not return as a second harness-configuration path.
[ ! -e config/llm/extra-openai-models.yaml ] \
    || fail "obsolete llm model records returned"
[ ! -e config/orca ] \
    || fail "retired Orca overlay returned"
[ ! -e scripts/configure-orca ] \
    || fail "retired Orca overlay installer returned"
[ ! -e scripts/install-agentbus-adapters ] \
    || fail "retired AgentBus adapter installer returned"
[ ! -e scripts/install-agentsurface-shims ] \
    || fail "retired AgentSurface shim installer returned"

for manifest in config/resources/*.json; do
    /usr/bin/jq -e . "$manifest" >/dev/null \
        || fail "resource manifest is not valid JSON: $manifest"
done
/usr/bin/jq -e '.name == "agent"' config/resources/claude-plugin.json >/dev/null \
    || fail "Claude fleet plugin has the wrong name"
/usr/bin/jq -e '
    (.mcpServers | keys == ["shadcn"]) and
    .mcpServers.shadcn == {"command":"npx","args":["shadcn@latest","mcp"]}
' config/resources/mcp-servers.json >/dev/null \
    || fail "fixed MCP resources are not exactly the managed shadcn server"
/usr/bin/jq -e '.name == "agent" and .skills == "./skills/" and .interface.capabilities == ["Skills"]' \
    config/resources/codex-plugin.json >/dev/null \
    || fail "Codex fleet plugin is not strictly skills-only"
if grep -Ei '"(hooks|mcpServers|apps)"[[:space:]]*:' config/resources/codex-plugin.json >/dev/null; then
    fail "Codex fleet plugin declares a globally active non-skill surface"
fi
[ -z "$(find config/capabilities -type f -print 2>/dev/null)" ] \
    || fail "retired capability-pack templates returned"
if grep -RFq 'AGENTSTART_CAPABILITIES_ROOT' scripts config README.md docs 2>/dev/null; then
    fail "retired AGENTSTART_CAPABILITIES_ROOT remains in active repository surfaces"
fi
[ ! -e scripts/install-core-plugin ] \
    || fail "retired core-plugin installer returned"
[ ! -e config/core-plugin ] \
    || fail "retired core-plugin manifests returned"

# The installer links these into ~/.config/agentguidance and agentguidance
# renders every skill against them, so an empty or missing prompt ships
# broken skills to a fresh account.
for prompt in SYSTEM.md GUIDELINES.md TOOLS.md; do
    [ -s "prompts/agentguidance/$prompt" ] \
        || fail "extension prompt is missing or empty: prompts/agentguidance/$prompt"
done
# Persistent guidance is file-backed rather than delegated to harness memory,
# and fleet-specific personal guidance stays in AgentStart's extension layer.
grep -F 'Do not use harness-provided agent memory' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not reject harness-provided agent memory"
grep -F 'Place global personal guidance tied to the' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not keep fleet-specific personal guidance in AgentStart"
# Gist publication is a GitHub CLI operation over the durable wiki file. Pin
# both the create-and-open route and the existing-Gist route so agents do not
# fall back to a browser app or create a duplicate merely to open it.
grep -F 'gh gist create FILE --desc "…" --web' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not create and open a requested Gist with gh"
grep -F 'gh gist view GIST_ID --web' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not open an existing Gist with gh"
grep -F 'public indexing was explicitly' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not preserve secret/unlisted Gists by default"

# Content convergence is one function with one call site, because two lists of
# what "content" means would drift apart on the first step somebody adds to
# only one of them. --content runs it alone; the full install ends with it.
grep -q '^converge_repo_content() {$' scripts/install.sh \
    || fail "install.sh does not define converge_repo_content"
[ "$(grep -c '^converge_repo_content$' scripts/install.sh)" -eq 1 ] \
    || fail "converge_repo_content must have exactly one call site in the full install"
grep -q -- '--content)' scripts/install.sh \
    || fail "install.sh does not accept --content"
for content_step in remove_retired_home_guidance link_extension_prompts \
    remove_retired_llm_config remove_legacy_global_skills \
    remove_retired_core_plugin remove_retired_pack_skills \
    link_agent_guidance; do
    [ "$(grep -c "^ *$content_step\$" scripts/install.sh)" -eq 1 ] \
        || fail "content step is called from more than one place: $content_step"
done
# The cheap path installs nothing: no formula, no fetch, no third-party pack.
content_body=$(sed -n '/^converge_repo_content() {$/,/^}$/p' scripts/install.sh)
printf '%s' "$content_body" | grep -Eq 'install_or_upgrade_formula|install_private_skill_pack|curl|npm install' \
    && fail "converge_repo_content installs or downloads something; it must only converge repository content"
printf '%s' "$content_body" | grep -q 'sync-skills' \
    || fail "converge_repo_content does not run the skill sync"

# Global advice belongs in the operator extension prompts, so the harness
# guidance source stays deliberately empty; the tripwire keeps advice from accreting
# back into every session.
[ -f prompts/AGENTS.md ] \
    || fail "the harness guidance source is missing: prompts/AGENTS.md"
[ ! -s prompts/AGENTS.md ] \
    || fail "prompts/AGENTS.md should stay empty — global advice belongs in the operator extension prompts"

# This checkout participates in its own agent* scan: the fleet skill is how a
# session reads the dependency map, and the map is the skill's payload. The
# fleet convention ships agents/openai.yaml beside every SKILL.md and the
# skill directory must be self-contained — the skills tool ships it whole.
[ -f skills/fleet/SKILL.md ] \
    || fail "the fleet skill is missing: skills/fleet/SKILL.md"
grep -q '^name: fleet$' skills/fleet/SKILL.md \
    || fail "the fleet skill frontmatter does not name itself"
[ -f skills/fleet/agents/openai.yaml ] \
    || fail "the fleet skill is missing its agents/openai.yaml manifest"
[ -s skills/fleet/MAP.md ] \
    || fail "the fleet dependency map is missing: skills/fleet/MAP.md"
grep -q '```mermaid' skills/fleet/MAP.md \
    || fail "the fleet dependency map has no mermaid diagram"
if grep -F '../' skills/fleet/SKILL.md >/dev/null; then
    fail "the fleet skill reaches outside its own directory and would ship broken"
fi
grep -F '"tend"' site/scripts/snapshot-fleet-resources.mjs >/dev/null \
    || fail "the fleet resource catalog omits tend"
jq -e '.skills[] | select(.id == "tend")' site/public/fleet-resources.json >/dev/null \
    || fail "the fleet resource snapshot omits tend"
if jq -e '.skills[] | select(.id == "supervise")' site/public/fleet-resources.json >/dev/null; then
    fail "the fleet resource snapshot still publishes supervise"
fi
grep -F '"chats"' site/scripts/snapshot-fleet-resources.mjs >/dev/null \
    || fail "the fleet resource catalog omits chats"
jq -e '.skills[] | select(.id == "chats")' site/public/fleet-resources.json >/dev/null \
    || fail "the fleet resource snapshot omits chats"

# Model invocability is one portable fact in SKILL.md. The common-pack render
# derives Codex's inverse product field; source manifests must not become a
# second, independently maintained policy.
if grep -H '^  allow_implicit_invocation:' skills/*/agents/openai.yaml; then
    fail "source OpenAI manifests contain rendered invocation policy"
fi
explicit_model_skills=$(
    for skill_file in skills/*/SKILL.md; do
        grep -q '^disable-model-invocation: true$' "$skill_file" || continue
        skill_dir=${skill_file%/SKILL.md}
        printf '%s\n' "${skill_dir##*/}"
    done | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
)
[ -z "$explicit_model_skills" ] \
    || fail "explicit-only skill policy drifted: $explicit_model_skills"

# The fleet agent contract: config/agent-contract/schema.json is normative and
# scripts/validate-agent-contract.ts is its dependency-free enforcement. The two
# are kept honest by a fixture per rule, so the test file is the thing that
# fails when they drift apart rather than a fleet CLI failing much later.
[ -f config/agent-contract/schema.json ] \
    || fail "the agent contract schema is missing"
[ -f config/agent-contract/README.md ] \
    || fail "the agent contract has no explanation for the repositories adopting it"
[ -x scripts/validate-agent-contract.ts ] \
    || fail "scripts/validate-agent-contract.ts must be executable"
# The validator executes the schema rather than restating it; losing the
# interpreter would silently return this to two authorships of one rule set.
[ -f scripts/json-schema-subset.ts ] \
    || fail "the schema interpreter is missing; the validator would be mirroring the schema again"
grep -q 'json-schema-subset' scripts/validate-agent-contract.ts \
    || fail "the agent contract validator no longer executes config/agent-contract/schema.json"
[ -f config/agent-contract/example.json ] \
    || fail "the agent contract has no worked example for the repositories adopting it"
bun test tests/agent-contract.test.ts
bun test tests/install-agent-clis.test.ts

# Prove the executable rejects, not just the exported function: a validator that
# only ever runs green in a unit test is a validator nobody has actually used.
contract_probe=$(mktemp)
printf '%s' '{"schema_version":1,"ok":true,"data":{"contract_version":1}}' > "$contract_probe"
if scripts/validate-agent-contract.ts --file "$contract_probe" >/dev/null 2>&1; then
    rm -f "$contract_probe"
    fail "the agent contract validator accepted a contract with no meta or commands"
fi
rm -f "$contract_probe"

# Cross-project guidance lives in the wiki, not in this repository; a
# guidance/ directory reappearing here means the decision reversed silently.
[ ! -e guidance ] \
    || fail "cross-project guidance moved to the wiki (tool-advertisement-policy); do not grow guidance/ back"

# Public-repo hygiene: everything resolves from $HOME, so an absolute path into
# a home directory is an account-name assumption leaking back in.
# The sweep covers tests/ as well, so both patterns are assembled rather than
# written out: a guard that spells what it hunts for matches its own source and
# can only pass by exempting itself.
hygiene_paths="scripts prompts config skills tests README.md AGENTS.md CONTEXT.md"
home_literal="/$(printf 'Users')/"
# shellcheck disable=SC2086 # $hygiene_paths is a deliberate list of targets.
if grep -rn "$home_literal" $hygiene_paths 2>/dev/null; then
    fail "a literal home-directory path assumes an account name; resolve from \$HOME instead"
fi
# The same rule for the operator's account name, which is knowable at runtime
# and therefore never needs to be written down.
operator_account=$(id -un)
# shellcheck disable=SC2086 # $hygiene_paths is a deliberate list of targets.
if grep -rn "$operator_account" $hygiene_paths 2>/dev/null; then
    fail "the operator's account name is spelled in the repository; resolve it at runtime"
fi
[ -s LICENSE ] || fail "public repository is missing its LICENSE"

# The post-sync hook is how agentguidance's templates survive the scan:
# sync-skills must run a participant's executable scripts/post-sync right
# after its skills land, and a failing hook must name the project.
# shellcheck disable=SC2016 # Match the literal hook invocation.
grep -F '"$project/scripts/post-sync"' scripts/sync-skills >/dev/null \
    || fail "sync-skills does not run a participant's post-sync hook"
grep -F 'post-sync hook failed' scripts/sync-skills >/dev/null \
    || fail "sync-skills does not propagate a failing post-sync hook"

skip_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-validate.XXXXXX")
trap 'rm -rf "$skip_test_dir"' EXIT

# Bare harness shims route through AgentLaunch, and the recursion sentinel
# keeps AgentLaunch-managed child processes from entering the shim again.
shim_home="$skip_test_dir/shim-home"
shim_bin="$skip_test_dir/shim-bin"
shim_real_bin="$skip_test_dir/shim-real-bin"
mkdir -p "$shim_home" "$shim_bin" "$shim_real_bin"
cat >"$shim_bin/agentlaunch" <<'EOF'
#!/bin/bash
printf 'agentlaunch'
printf ' <%s>' "$@"
printf '\n'
EOF
chmod +x "$shim_bin/agentlaunch"
for shim_harness in claude codex; do
    cat >"$shim_real_bin/$shim_harness" <<'EOF'
#!/bin/bash
printf 'real %s' "$(basename "$0")"
printf ' <%s>' "$@"
printf '\n'
EOF
    chmod +x "$shim_real_bin/$shim_harness"
done
HOME="$shim_home" \
    PATH="$shim_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/scripts/install-agentlaunch-shims" >/dev/null
for shim_harness in claude codex; do
    shim="$shim_home/.local/share/agentlaunch/shims/$shim_harness"
    [ -x "$shim" ] || fail "AgentLaunch shim is missing or not executable: $shim"
    grep -F "AgentStart-managed AgentLaunch shim" "$shim" >/dev/null \
        || fail "AgentLaunch shim is missing its ownership marker: $shim"
    grep -F "exec agentlaunch --x-harness $shim_harness" "$shim" >/dev/null \
        || fail "AgentLaunch shim does not route $shim_harness through agentlaunch"
done
shim_output=$(
    AGENTLAUNCH_LAUNCH='' AGENTLAUNCH_SHIM_BYPASS='' \
        PATH="$shim_home/.local/share/agentlaunch/shims:$shim_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        "$shim_home/.local/share/agentlaunch/shims/claude" --version
)
[ "$shim_output" = 'agentlaunch <--x-harness> <claude> <--version>' ] \
    || fail "AgentLaunch shim did not route a bare harness launch: $shim_output"
shim_bypass_output=$(
    AGENTLAUNCH_LAUNCH=1 \
        PATH="$shim_home/.local/share/agentlaunch/shims:$shim_real_bin:$shim_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        "$shim_home/.local/share/agentlaunch/shims/claude" --version
)
[ "$shim_bypass_output" = 'real claude <--version>' ] \
    || fail "AgentLaunch shim did not bypass itself under the recursion sentinel: $shim_bypass_output"

# Terminal Control's named-session daemon must leave the invoking harness's
# process group, while every other command remains a direct pass-through. The
# fake payload reports its process identity and arguments so this test proves
# both properties without starting a persistent daemon.
termctrl_shim_home="$skip_test_dir/termctrl-shim-home"
termctrl_fake="$termctrl_shim_home/.local/libexec/agentstart/terminal-control/termctrl"
mkdir -p "$(dirname "$termctrl_fake")"
cat >"$termctrl_fake" <<'PYTHON'
#!/usr/bin/python3
import json
import os
import sys

print(json.dumps({
    "pid": os.getpid(),
    "pgid": os.getpgrp(),
    "sid": os.getsid(0),
    "args": sys.argv[1:],
}))
raise SystemExit(int(os.environ.get("TERMCTRL_FAKE_EXIT", "0")))
PYTHON
chmod 0755 "$termctrl_fake"
termctrl_direct=$(
    HOME="$termctrl_shim_home" \
        "$root/config/terminal-control/termctrl" --version
)
printf '%s\n' "$termctrl_direct" | /usr/bin/jq -e \
    '.args == ["--version"]' >/dev/null \
    || fail "Terminal Control shim changed pass-through arguments"
termctrl_detached=$(
    HOME="$termctrl_shim_home" \
        "$root/config/terminal-control/termctrl" start proof -- /bin/true
)
printf '%s\n' "$termctrl_detached" | /usr/bin/jq -e \
    '.pid == .pgid and .pid == .sid and
     .args == ["start", "proof", "--", "/bin/true"]' >/dev/null \
    || fail "Terminal Control start did not execute in a detached session"
set +e
HOME="$termctrl_shim_home" TERMCTRL_FAKE_EXIT=23 \
    "$root/config/terminal-control/termctrl" start exit-proof >/dev/null
termctrl_exit_status=$?
set -e
[ "$termctrl_exit_status" -eq 23 ] \
    || fail "Terminal Control shim did not preserve the launcher exit status"

# Retired integrations are removed only when they carry exact AgentStart or
# predecessor-owned markers. Independent files that merely live at old paths
# must survive.
cleanup_home="$skip_test_dir/cleanup-home"
cleanup_code_root="$skip_test_dir/cleanup-code"
mkdir -p \
    "$cleanup_home/.local/bin" \
    "$cleanup_home/.local/share/agentsurface/shims" \
    "$cleanup_home/.omp/agent/extensions" \
    "$cleanup_home/.claude/skills" \
    "$cleanup_home/.claude" \
    "$cleanup_home/.codex" \
    "$cleanup_home/.config/amp/plugins" \
    "$cleanup_home/.config/devin" \
    "$cleanup_home/.factory" \
    "$cleanup_home/.gemini/config" \
    "$cleanup_home/.cursor" \
    "$cleanup_home/.commandcode" \
    "$cleanup_home/.grok/hooks" \
    "$cleanup_home/.copilot/hooks" \
    "$cleanup_home/.openclaude" \
    "$cleanup_home/.kimi-code" \
    "$cleanup_home/.hermes/plugins/orca-status" \
    "$cleanup_code_root/agentbus/src" \
    "$cleanup_code_root/agentbus/plugins/claude" \
    "$cleanup_code_root/agentsurface/src"
touch \
    "$cleanup_code_root/agentbus/src/main.ts" \
    "$cleanup_code_root/agentbus/plugins/claude/.keep" \
    "$cleanup_code_root/agentsurface/src/main.ts"
ln -s "$cleanup_code_root/agentbus/src/main.ts" "$cleanup_home/.local/bin/agentbus"
ln -s "$cleanup_code_root/agentsurface/src/main.ts" "$cleanup_home/.local/bin/agentsurface"
ln -s "$cleanup_code_root/agentbus/plugins/claude" "$cleanup_home/.claude/skills/agentbus"
printf '# AgentStart-managed agentsurface shim: old\n' \
    >"$cleanup_home/.local/share/agentsurface/shims/claude"
printf '# independent shim\n' \
    >"$cleanup_home/.local/share/agentsurface/shims/codex"
printf '// @orca-managed-pi-extension\n' \
    >"$cleanup_home/.omp/agent/extensions/orca-agent-status.ts"
printf '// independent extension\n' \
    >"$cleanup_home/.omp/agent/extensions/orca-prefill.ts"
printf '// Managed by Orca. Do not edit\n' \
    >"$cleanup_home/.config/amp/plugins/orca-agent-status.ts"
cat >"$cleanup_home/.claude/settings.json" <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$cleanup_home/.orca/agent-hooks/claude-hook.sh"
          },
          {
            "type": "command",
            "command": "keep-claude"
          }
        ]
      },
      {
        "matcher": "remove-empty",
        "hooks": [
          {
            "type": "command",
            "command": "$cleanup_home/.orca/agent-hooks/claude-hook.sh"
          }
        ]
      }
    ]
  }
}
EOF
cat >"$cleanup_home/.codex/hooks.json" <<EOF
{
  "hooks": {
    "pre-command": [
      {
        "hooks": [
          {
            "command": "$cleanup_home/.orca/agent-hooks/codex-hook.sh"
          },
          {
            "command": "keep-codex"
          }
        ]
      }
    ]
  }
}
EOF
for hook_fixture in \
    ".config/devin/config.json:devin-hook.sh" \
    ".factory/settings.json:droid-hook.sh" \
    ".gemini/settings.json:gemini-hook.sh" \
    ".commandcode/settings.json:command-code-hook.sh" \
    ".openclaude/settings.json:openclaude-hook.sh"; do
    hook_file="$cleanup_home/${hook_fixture%%:*}"
    hook_name=${hook_fixture#*:}
    cat >"$hook_file" <<EOF
{
  "hooks": {
    "Stop": [
      {"hooks": [
        {"command": "$cleanup_home/.orca/agent-hooks/$hook_name"},
        {"command": "keep-nested-hook"}
      ]}
    ],
    "Direct": [
      {"command": "$cleanup_home/.orca/agent-hooks/$hook_name"},
      {"command": "keep-direct-hook"}
    ]
  }
}
EOF
done
cat >"$cleanup_home/.gemini/settings.json" <<'EOF'
{
  // Gemini accepts JSONC; Orca also installed PowerShell hooks on Windows.
  "hooks": {
    "Stop": [
      {"powershell": "powershell.exe -File C:\\Users\\fixture\\.orca\\agent-hooks\\gemini-hook.ps1"},
      {"command": "keep-gemini"},
    ],
  },
}
EOF
cat >"$cleanup_home/.cursor/hooks.json" <<EOF
{"version":1,"hooks":{"stop":[
  {"command":"$cleanup_home/.orca/agent-hooks/cursor-hook.sh"},
  {"command":"keep-cursor"}
]}}
EOF
cat >"$cleanup_home/.grok/hooks/orca-status.json" <<EOF
{"hooks":{"Stop":[{"hooks":[{"command":"$cleanup_home/.orca/agent-hooks/grok-hook.sh"}]}]}}
EOF
cat >"$cleanup_home/.copilot/hooks/orca.json" <<EOF
{"version":1,"hooks":{"Stop":[
  {"bash":"$cleanup_home/.orca/agent-hooks/copilot-hook.sh"},
  {"bash":"keep-copilot"}
]}}
EOF
cat >"$cleanup_home/.gemini/config/hooks.json" <<EOF
{"orca-status":{"Stop":[
  {"command":"$cleanup_home/.orca/agent-hooks/antigravity-hook.sh"},
  {"command":"keep-antigravity"}
]},"keep":{"value":true}}
EOF
cat >"$cleanup_home/.kimi-code/config.toml" <<EOF
keep = true

# >>> orca-managed-kimi-hooks (managed by Orca; do not edit) >>>
[[hooks]]
event = "Stop"
command = "$cleanup_home/.orca/agent-hooks/kimi-hook.sh"
# <<< orca-managed-kimi-hooks <<<
EOF
cat >"$cleanup_home/.hermes/config.yaml" <<'EOF'
plugins:
  enabled:
    - keep-hermes
    - orca-status
other: true
EOF
printf '# Managed by Orca. Do not edit; changes may be overwritten.\n' \
    >"$cleanup_home/.hermes/plugins/orca-status/plugin.yaml"
printf '# Managed by Orca. Do not edit; changes may be overwritten.\n' \
    >"$cleanup_home/.hermes/plugins/orca-status/__init__.py"
cat >"$cleanup_home/.codex/config.toml" <<'EOF'
model = "gpt"

# agentbus: bus sends from inside the sandbox need the daemon socket
[sandbox_workspace_write]
network_access = true

[profiles.default]
model = "gpt"
EOF
HOME="$cleanup_home" AGENTSTART_CODE_ROOT="$cleanup_code_root" \
    "$root/scripts/remove-retired-integrations" >/dev/null
[ ! -e "$cleanup_home/.local/bin/agentbus" ] \
    || fail "retired AgentBus CLI symlink was not removed"
[ -L "$cleanup_home/.local/bin/agentsurface" ] \
    || fail "live AgentSurface CLI symlink was removed by retired cleanup"
[ ! -e "$cleanup_home/.claude/skills/agentbus" ] \
    || fail "retired AgentBus Claude plugin was not removed"
[ ! -e "$cleanup_home/.local/share/agentsurface/shims/claude" ] \
    || fail "retired AgentSurface shim was not removed"
[ -e "$cleanup_home/.local/share/agentsurface/shims/codex" ] \
    || fail "independent shim at old AgentSurface path was removed"
[ ! -e "$cleanup_home/.omp/agent/extensions/orca-agent-status.ts" ] \
    || fail "retired Orca OMP extension was not removed"
[ -e "$cleanup_home/.omp/agent/extensions/orca-prefill.ts" ] \
    || fail "independent OMP extension was removed"
[ ! -e "$cleanup_home/.config/amp/plugins/orca-agent-status.ts" ] \
    || fail "retired Orca Amp plugin was not removed"
grep -F "$cleanup_home/.orca/agent-hooks/claude-hook.sh" "$cleanup_home/.claude/settings.json" >/dev/null \
    && fail "retired Orca Claude hook was not removed"
grep -F "$cleanup_home/.orca/agent-hooks/codex-hook.sh" "$cleanup_home/.codex/hooks.json" >/dev/null \
    && fail "retired Orca Codex hook was not removed"
grep -F 'keep-claude' "$cleanup_home/.claude/settings.json" >/dev/null \
    || fail "retired cleanup removed unrelated Claude hook"
grep -F 'keep-codex' "$cleanup_home/.codex/hooks.json" >/dev/null \
    || fail "retired cleanup removed unrelated Codex hook"
for hook_file in \
    "$cleanup_home/.config/devin/config.json" \
    "$cleanup_home/.factory/settings.json" \
    "$cleanup_home/.gemini/settings.json" \
    "$cleanup_home/.cursor/hooks.json" \
    "$cleanup_home/.commandcode/settings.json" \
    "$cleanup_home/.copilot/hooks/orca.json" \
    "$cleanup_home/.openclaude/settings.json"; do
    grep -F '.orca/agent-hooks/' "$hook_file" >/dev/null \
        && fail "retired Orca hook remained in $hook_file"
done
for hook_file in \
    "$cleanup_home/.config/devin/config.json" \
    "$cleanup_home/.factory/settings.json" \
    "$cleanup_home/.commandcode/settings.json" \
    "$cleanup_home/.openclaude/settings.json"; do
    grep -F 'keep-nested-hook' "$hook_file" >/dev/null \
        || fail "retired cleanup removed an unrelated nested hook from $hook_file"
    grep -F 'keep-direct-hook' "$hook_file" >/dev/null \
        || fail "retired cleanup removed an unrelated direct hook from $hook_file"
done
grep -F 'keep-gemini' "$cleanup_home/.gemini/settings.json" >/dev/null \
    || fail "retired cleanup removed an unrelated Gemini hook"
grep -F 'gemini-hook.' "$cleanup_home/.gemini/settings.json" >/dev/null \
    && fail "retired Gemini PowerShell hook remained"
[ ! -e "$cleanup_home/.grok/hooks/orca-status.json" ] \
    || fail "empty Orca-owned Grok hook file was not removed"
grep -F 'keep-cursor' "$cleanup_home/.cursor/hooks.json" >/dev/null \
    || fail "retired cleanup removed an unrelated Cursor hook"
grep -F 'keep-copilot' "$cleanup_home/.copilot/hooks/orca.json" >/dev/null \
    || fail "retired cleanup removed an unrelated Copilot hook"
grep -F 'antigravity-hook.' "$cleanup_home/.gemini/config/hooks.json" >/dev/null \
    && fail "retired Antigravity hook remained"
grep -F 'keep-antigravity' "$cleanup_home/.gemini/config/hooks.json" >/dev/null \
    || fail "retired cleanup removed an unrelated Antigravity hook"
grep -F 'orca-managed-kimi-hooks' "$cleanup_home/.kimi-code/config.toml" >/dev/null \
    && fail "retired Kimi hook block remained"
grep -F 'keep = true' "$cleanup_home/.kimi-code/config.toml" >/dev/null \
    || fail "retired cleanup removed unrelated Kimi configuration"
[ ! -e "$cleanup_home/.hermes/plugins/orca-status" ] \
    || fail "retired Hermes plugin was not removed"
grep -F 'orca-status' "$cleanup_home/.hermes/config.yaml" >/dev/null \
    && fail "retired Hermes plugin remained enabled"
grep -F 'keep-hermes' "$cleanup_home/.hermes/config.yaml" >/dev/null \
    || fail "retired cleanup removed an unrelated Hermes plugin"
grep -F 'other: true' "$cleanup_home/.hermes/config.yaml" >/dev/null \
    || fail "retired cleanup damaged unrelated Hermes configuration"
grep -F 'agentbus: bus sends' "$cleanup_home/.codex/config.toml" >/dev/null \
    && fail "retired AgentBus Codex sandbox marker was not removed"
grep -F 'network_access = true' "$cleanup_home/.codex/config.toml" >/dev/null \
    && fail "retired AgentBus Codex sandbox override was not removed"
grep -F '[profiles.default]' "$cleanup_home/.codex/config.toml" >/dev/null \
    || fail "retired cleanup damaged unrelated Codex config"

independent_cleanup_home="$skip_test_dir/independent-cleanup-home"
mkdir -p "$independent_cleanup_home/.grok/hooks"
printf '{"version":1,"hooks":{}}\n' \
    >"$independent_cleanup_home/.grok/hooks/orca-status.json"
HOME="$independent_cleanup_home" AGENTSTART_CODE_ROOT="$cleanup_code_root" \
    "$root/scripts/remove-retired-integrations" >/dev/null
[ -e "$independent_cleanup_home/.grok/hooks/orca-status.json" ] \
    || fail "independent empty hook file was removed"

bad_cleanup_home="$skip_test_dir/bad-cleanup-home"
mkdir -p "$bad_cleanup_home/.codex"
cat >"$bad_cleanup_home/.codex/config.toml" <<'EOF'
# agentbus: bus sends from inside the sandbox need the daemon socket
[sandbox_workspace_write]
network_access = false
EOF
set +e
bad_cleanup_output=$(
    HOME="$bad_cleanup_home" AGENTSTART_CODE_ROOT="$cleanup_code_root" \
        "$root/scripts/remove-retired-integrations" 2>&1
)
bad_cleanup_status=$?
set -e
[ "$bad_cleanup_status" -ne 0 ] \
    || fail "retired cleanup removed a changed AgentBus sandbox block"
printf '%s\n' "$bad_cleanup_output" \
    | grep -F 'changed AgentBus sandbox block' >/dev/null \
    || fail "retired cleanup did not explain changed sandbox-block refusal"
grep -F 'network_access = false' "$bad_cleanup_home/.codex/config.toml" >/dev/null \
    || fail "retired cleanup changed a refused sandbox block"

# Pi retirement refuses to delete producer state until the corresponding
# deployed commands prove their new Pi-free contracts. One shared set of clean
# Git checkouts backs the hermetic command links used by the fixtures below.
retired_pi_contract_code_root="$skip_test_dir/retired-pi-contract-code"
mkdir -p \
    "$retired_pi_contract_code_root/agentlaunch/src" \
    "$retired_pi_contract_code_root/agentsurface/src" \
    "$retired_pi_contract_code_root/agentchats/bin" \
    "$retired_pi_contract_code_root/codex-swap/src/cli"
retired_pi_contract_code_root=$(cd -P -- "$retired_pi_contract_code_root" && pwd)
retired_pi_lock_assert="$retired_pi_contract_code_root/assert-no-retirement-lock-fd"
cat >"$retired_pi_lock_assert" <<'EOF'
#!/bin/bash
set -euo pipefail
/usr/bin/perl -Mstrict -Mwarnings -e '
    my $path = "$ENV{HOME}/.local/state/agentstart/retirement.lock";
    my @lock = stat($path);
    @lock or die "retirement lock is missing during deployment proof\n";
    for my $fd (3 .. 255) {
        open(my $handle, "<&=$fd") or next;
        my @opened = stat($handle);
        die "deployment proof inherited retirement lock fd $fd\n"
            if @opened && $opened[0] == $lock[0] && $opened[1] == $lock[1];
        close $handle or die "close inspected deployment fd $fd: $!\n";
    }
'
EOF
chmod +x "$retired_pi_lock_assert"
export AGENTSTART_TEST_PI_LOCK_ASSERT="$retired_pi_lock_assert"
cat >"$retired_pi_contract_code_root/agentlaunch/src/main.ts" <<'EOF'
#!/bin/bash
set -euo pipefail
"$AGENTSTART_TEST_PI_LOCK_ASSERT"
case "$*" in
    'x-catalog --x-json')
        printf '%s\n' '{"ok":true,"data":{"harnesses":[{"harness":"claude"},{"harness":"codex"}]}}'
        ;;
    '--x-harness pi --x-dry-run')
        printf '%s\n' 'harness "pi" is retired; choose claude or codex' >&2
        exit 2
        ;;
    *) exit 64 ;;
esac
EOF
cat >"$retired_pi_contract_code_root/agentsurface/src/main.ts" <<'EOF'
#!/bin/bash
set -euo pipefail
"$AGENTSTART_TEST_PI_LOCK_ASSERT"
[ "${1:-} ${2:-}" = 'guide --json' ] || exit 64
printf '%s\n' '{"ok":true,"data":{"contract":"fixture"}}'
EOF
cat >"$retired_pi_contract_code_root/agentchats/bin/agentchats" <<'EOF'
#!/bin/bash
set -euo pipefail
"$AGENTSTART_TEST_PI_LOCK_ASSERT"
exit 0
EOF
printf '%s\n' 'export const retirementFixture = true;' \
    >"$retired_pi_contract_code_root/codex-swap/src/cli/main.ts"
chmod +x \
    "$retired_pi_contract_code_root/agentlaunch/src/main.ts" \
    "$retired_pi_contract_code_root/agentsurface/src/main.ts" \
    "$retired_pi_contract_code_root/agentchats/bin/agentchats"
for retired_pi_contract_repo in agentlaunch agentsurface agentchats codex-swap; do
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" init -q -b main
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        config user.email fixture@example.invalid
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        config user.name Fixture
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        remote add origin "git@github.com:possibilities/$retired_pi_contract_repo.git"
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" add .
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        commit -q -m 'Pi-free deployment fixture'
    retired_pi_contract_sha=$(git -C \
        "$retired_pi_contract_code_root/$retired_pi_contract_repo" rev-parse HEAD)
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        update-ref refs/remotes/origin/main "$retired_pi_contract_sha"
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        config branch.main.remote origin
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        config branch.main.merge refs/heads/main
done
retired_pi_contract_agentlaunch_retirement_sha=$(git -C \
    "$retired_pi_contract_code_root/agentlaunch" rev-parse HEAD)
export AGENTSTART_TEST_PI_CODE_ROOT="$retired_pi_contract_code_root"
export AGENTSTART_TEST_PI_AGENTLAUNCH_RETIREMENT_SHA="$retired_pi_contract_agentlaunch_retirement_sha"
retired_pi_contract_agentsurface_retirement_sha=$(git -C \
    "$retired_pi_contract_code_root/agentsurface" rev-parse HEAD)
export AGENTSTART_TEST_PI_AGENTSURFACE_RETIREMENT_SHA="$retired_pi_contract_agentsurface_retirement_sha"
retired_pi_contract_codex_swap_retirement_sha=$(git -C \
    "$retired_pi_contract_code_root/codex-swap" rev-parse HEAD)
export AGENTSTART_TEST_PI_CODEX_SWAP_RETIREMENT_SHA="$retired_pi_contract_codex_swap_retirement_sha"
# Model the live checkout precisely: pushed main has advanced beyond the
# reviewed scrub, and one clean local commit sits above pushed main. The gate
# must prove reviewed scrub -> pushed main -> deployed checkout rather than
# pinning an old tip or accepting an unrelated latest commit.
printf '%s\n' 'safe pushed contract fixture' \
    >"$retired_pi_contract_code_root/codex-swap/pushed-contract"
git -C "$retired_pi_contract_code_root/codex-swap" add pushed-contract
git -C "$retired_pi_contract_code_root/codex-swap" \
    commit -q -m 'Safe pushed post-scrub fixture'
retired_pi_contract_codex_swap_pushed_sha=$(git -C \
    "$retired_pi_contract_code_root/codex-swap" rev-parse HEAD)
git -C "$retired_pi_contract_code_root/codex-swap" update-ref \
    refs/remotes/origin/main "$retired_pi_contract_codex_swap_pushed_sha"
printf '%s\n' 'protected local contract fixture' \
    >"$retired_pi_contract_code_root/codex-swap/protected-contract"
git -C "$retired_pi_contract_code_root/codex-swap" add protected-contract
git -C "$retired_pi_contract_code_root/codex-swap" \
    commit -q -m 'Protected local contract fixture'
retired_pi_contract_codex_swap_checkout_sha=$(git -C \
    "$retired_pi_contract_code_root/codex-swap" rev-parse HEAD)
# This mirrors the operator-owned rollback backup in the live codex-swap
# checkout. The retirement gate must preserve this exact, proved exception
# while continuing to reject every other untracked working-tree path.
mkdir -p \
    "$retired_pi_contract_code_root/codex-swap/.cma-backup-pre-2.10.0-20260831-160414/runtime"
printf 'fixture rollback\n' >"$retired_pi_contract_code_root/codex-swap/.cma-backup-pre-2.10.0-20260831-160414/rotation.js"
printf 'fixture proxy\n' >"$retired_pi_contract_code_root/codex-swap/.cma-backup-pre-2.10.0-20260831-160414/runtime-rotation-proxy.js"
printf 'fixture selector\n' \
    >"$retired_pi_contract_code_root/codex-swap/.cma-backup-pre-2.10.0-20260831-160414/runtime/rotation-account-selection.js"
for retired_pi_contract_repo in agentlaunch agentsurface; do
    printf '%s\n' 'protected local contract fixture' \
        >"$retired_pi_contract_code_root/$retired_pi_contract_repo/protected-contract"
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        add protected-contract
    git -C "$retired_pi_contract_code_root/$retired_pi_contract_repo" \
        commit -q -m 'Protected local contract fixture'
done
retired_pi_contract_agentlaunch_sha=$(git -C \
    "$retired_pi_contract_code_root/agentlaunch" rev-parse HEAD)

install_retired_pi_codex_swap_contract() {
    local fixture_home="$1"
    fixture_home=$(cd -P -- "$fixture_home" && pwd)
    mkdir -p "$fixture_home/.local/bin" "$fixture_home/.local/state/codex-swap"
    cat >"$fixture_home/.local/bin/codex-swap" <<EOF
#!/usr/bin/env bash
# codex-swap-installer-owned:v1
exec /usr/bin/true $retired_pi_contract_code_root/codex-swap/src/cli/main.ts "\$@"
EOF
    chmod 755 "$fixture_home/.local/bin/codex-swap"
    cat >"$fixture_home/.local/state/codex-swap/install-receipt" <<EOF
codex-swap-installer-owned:v1
root=$retired_pi_contract_code_root/codex-swap
bin=$fixture_home/.local/bin
EOF
    chmod 600 "$fixture_home/.local/state/codex-swap/install-receipt"
}

install_retired_pi_agentlaunch_contract() {
    local fixture_home="$1"
    install_retired_pi_codex_swap_contract "$fixture_home"
    mkdir -p "$fixture_home/.local/bin" "$fixture_home/.local/state/agentlaunch"
    ln -s "$retired_pi_contract_code_root/agentlaunch/src/main.ts" \
        "$fixture_home/.local/bin/agentlaunch"
    printf '%s\n' "$retired_pi_contract_agentlaunch_sha" \
        >"$fixture_home/.local/state/agentlaunch/deployed-sha"
    chmod 600 "$fixture_home/.local/state/agentlaunch/deployed-sha"
}

install_retired_pi_agentsurface_contract() {
    local fixture_home="$1"
    mkdir -p "$fixture_home/.local/bin"
    ln -s "$retired_pi_contract_code_root/agentsurface/src/main.ts" \
        "$fixture_home/.local/bin/agentsurface"
}

install_retired_pi_agentchats_contract() {
    local fixture_home="$1"
    mkdir -p "$fixture_home/.local/bin"
    ln -s "$retired_pi_contract_code_root/agentchats/bin/agentchats" \
        "$fixture_home/.local/bin/agentchats"
}

# AgentChats removed its completed one-time migration helpers after a7dd713.
# AgentStart retains refusal when the old retry receipt says that migration did
# not finish, without coupling the cleanup to a particular search backend.
pending_agentchats_home="$skip_test_dir/pending-agentchats-retirement-home"
mkdir -p \
    "$pending_agentchats_home/.pi" \
    "$pending_agentchats_home/.local/state/agentchats"
install_retired_pi_agentchats_contract "$pending_agentchats_home"
printf '%s\n' '{"version":1,"pending":true}' \
    >"$pending_agentchats_home/.local/state/agentchats/pi-retirement-v1.pending.json"
set +e
pending_agentchats_output=$(AGENTSTART_PI_CLEANUP_HOME="$pending_agentchats_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
pending_agentchats_status=$?
set -e
[ "$pending_agentchats_status" -ne 0 ] \
    || fail "retired cleanup accepted the completed AgentChats retry receipt"
printf '%s\n' "$pending_agentchats_output" \
    | grep -F 'completed AgentChats retirement receipt remains' >/dev/null \
    || fail "retired cleanup did not explain the stale AgentChats retry receipt"
[ -d "$pending_agentchats_home/.pi" ] \
    || fail "retired cleanup mutated Pi state before refusing the AgentChats retry receipt"

make_retired_pi_claim_fixture() {
    local fixture_home="$1"
    local target="$fixture_home/.local/share/agentstart/resources/pi"
    mkdir -p "$target"
    printf 'retirement-owned fixture\n' >"$target/owned"
}

make_retired_pi_process_fixture() {
    local fixture_home="$1"
    local ps_fixture="$fixture_home/fake-ps"
    cat >"$ps_fixture" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$#" -eq 2 ] && [ "$1" = -axo ] && [ "$2" = 'pid=,comm=,args=' ] || exit 64
if [ -e "$AGENTSTART_TEST_PI_PROCESS_TRIGGER" ]; then
    printf '%s\n' '424242 pi pi --model fixture'
else
    printf '%s\n' '424241 bash bash fixture'
fi
EOF
    chmod +x "$ps_fixture"
}

make_retired_pi_viewer_checkout() {
    local fixture_home="$1"
    local checkout="$fixture_home/code/pi-viewer"
    mkdir -p "$checkout"
    cat >"$checkout/README.md" <<'EOF'
# Retired

This project has been retired. Its former product, launcher, dependencies,
and source checkout are no longer maintained or distributed from this branch.
EOF
    printf 'fixture license\n' >"$checkout/LICENSE"
    git -C "$checkout" init -q -b main
    git -C "$checkout" config user.email fixture@example.invalid
    git -C "$checkout" config user.name Fixture
    git -C "$checkout" remote add origin git@github.com:possibilities/pi-viewer.git
    git -C "$checkout" add LICENSE README.md
    git -C "$checkout" commit -q -m Retired
    git -C "$checkout" update-ref refs/remotes/origin/main \
        "$(git -C "$checkout" rev-parse HEAD)"
    git -C "$checkout" config branch.main.remote origin
    git -C "$checkout" config branch.main.merge refs/heads/main
}

# Protected local contract commits may sit above pushed main, and pushed main
# may sit above a reviewed retirement commit. A remote ref outside that proved
# ancestry chain must still block cleanup before dedicated state is touched.
wrong_codex_swap_remote_home="$skip_test_dir/wrong-codex-swap-retirement-remote-home"
mkdir -p "$wrong_codex_swap_remote_home/.pi"
install_retired_pi_codex_swap_contract "$wrong_codex_swap_remote_home"
wrong_codex_swap_tree=$(git -C "$retired_pi_contract_code_root/codex-swap" write-tree)
wrong_codex_swap_sha=$(printf '%s\n' 'Wrong pushed codex-swap fixture' \
    | git -C "$retired_pi_contract_code_root/codex-swap" commit-tree "$wrong_codex_swap_tree")
git -C "$retired_pi_contract_code_root/codex-swap" update-ref \
    refs/remotes/origin/main "$wrong_codex_swap_sha"
set +e
wrong_codex_swap_remote_output=$(AGENTSTART_PI_CLEANUP_HOME="$wrong_codex_swap_remote_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
wrong_codex_swap_remote_status=$?
set -e
git -C "$retired_pi_contract_code_root/codex-swap" update-ref \
    refs/heads/main "$retired_pi_contract_codex_swap_checkout_sha"
git -C "$retired_pi_contract_code_root/codex-swap" update-ref \
    refs/remotes/origin/main "$retired_pi_contract_codex_swap_pushed_sha"
[ "$wrong_codex_swap_remote_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted the wrong pushed codex-swap commit"
printf '%s\n' "$wrong_codex_swap_remote_output" \
    | grep -F 'required Pi-free codex-swap checkout does not contain its pushed main ref' >/dev/null \
    || fail "retired Pi cleanup did not explain the wrong codex-swap remote refusal"
[ -d "$wrong_codex_swap_remote_home/.pi" ] \
    || fail "retired Pi cleanup mutated state with the wrong codex-swap remote"

wrong_agentlaunch_remote_home="$skip_test_dir/wrong-agentlaunch-retirement-remote-home"
mkdir -p "$wrong_agentlaunch_remote_home/.pi"
install_retired_pi_agentlaunch_contract "$wrong_agentlaunch_remote_home"
git -C "$retired_pi_contract_code_root/agentlaunch" \
    update-ref refs/remotes/origin/main "$retired_pi_contract_agentlaunch_sha"
set +e
wrong_agentlaunch_remote_output=$(AGENTSTART_PI_CLEANUP_HOME="$wrong_agentlaunch_remote_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
wrong_agentlaunch_remote_status=$?
set -e
git -C "$retired_pi_contract_code_root/agentlaunch" update-ref \
    refs/remotes/origin/main "$retired_pi_contract_agentlaunch_retirement_sha"
[ "$wrong_agentlaunch_remote_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted the wrong pushed AgentLaunch commit"
printf '%s\n' "$wrong_agentlaunch_remote_output" \
    | grep -F 'pushed AgentLaunch main is not the reviewed Pi retirement commit' >/dev/null \
    || fail "retired Pi cleanup did not explain the wrong AgentLaunch remote refusal"
[ -d "$wrong_agentlaunch_remote_home/.pi" ] \
    || fail "retired Pi cleanup mutated state with the wrong AgentLaunch remote"

wrong_agentsurface_remote_home="$skip_test_dir/wrong-agentsurface-retirement-remote-home"
mkdir -p "$wrong_agentsurface_remote_home/.pi"
install_retired_pi_agentsurface_contract "$wrong_agentsurface_remote_home"
git -C "$retired_pi_contract_code_root/agentsurface" update-ref \
    refs/remotes/origin/main \
    "$(git -C "$retired_pi_contract_code_root/agentsurface" rev-parse HEAD)"
set +e
wrong_agentsurface_remote_output=$(AGENTSTART_PI_CLEANUP_HOME="$wrong_agentsurface_remote_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
wrong_agentsurface_remote_status=$?
set -e
git -C "$retired_pi_contract_code_root/agentsurface" update-ref \
    refs/remotes/origin/main "$retired_pi_contract_agentsurface_retirement_sha"
[ "$wrong_agentsurface_remote_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted the wrong pushed AgentSurface commit"
printf '%s\n' "$wrong_agentsurface_remote_output" \
    | grep -F 'pushed AgentSurface main is not the reviewed Pi retirement commit' >/dev/null \
    || fail "retired Pi cleanup did not explain the wrong AgentSurface remote refusal"
[ -d "$wrong_agentsurface_remote_home/.pi" ] \
    || fail "retired Pi cleanup mutated state with the wrong AgentSurface remote"

# Process absence is checked before claims, after the claim-all barrier, and in
# the final audit. A process appearing at any one of those boundaries must
# fail the run instead of racing executable or state deletion.
initial_process_home="$skip_test_dir/retired-pi-initial-process-home"
initial_process_trigger="$initial_process_home/process-present"
mkdir -p "$initial_process_home/.pi"
make_retired_pi_process_fixture "$initial_process_home"
: >"$initial_process_trigger"
set +e
initial_process_output=$(AGENTSTART_PI_CLEANUP_HOME="$initial_process_home" \
    AGENTSTART_TEST_PI_PS_BIN="$initial_process_home/fake-ps" \
    AGENTSTART_TEST_PI_PROCESS_TRIGGER="$initial_process_trigger" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
initial_process_status=$?
set -e
[ "$initial_process_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted an initially live Pi process"
printf '%s\n' "$initial_process_output" | grep -F 'a live retired Pi process blocks cleanup' >/dev/null \
    || fail "retired Pi cleanup did not explain its initial process refusal"
[ -d "$initial_process_home/.pi" ] \
    || fail "retired Pi cleanup mutated state while an initial process was live"

post_claim_process_home="$skip_test_dir/retired-pi-post-claim-process-home"
post_claim_process_trigger="$post_claim_process_home/process-present"
post_claim_process_hook="$post_claim_process_home/start-process-after-claims"
make_retired_pi_claim_fixture "$post_claim_process_home"
make_retired_pi_process_fixture "$post_claim_process_home"
cat >"$post_claim_process_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
: >"$AGENTSTART_TEST_PI_PROCESS_TRIGGER"
EOF
chmod +x "$post_claim_process_hook"
set +e
post_claim_process_output=$(AGENTSTART_PI_CLEANUP_HOME="$post_claim_process_home" \
    AGENTSTART_TEST_PI_PS_BIN="$post_claim_process_home/fake-ps" \
    AGENTSTART_TEST_PI_PROCESS_TRIGGER="$post_claim_process_trigger" \
    AGENTSTART_TEST_PI_AFTER_CLAIMS_HOOK="$post_claim_process_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
post_claim_process_status=$?
set -e
[ "$post_claim_process_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a process started after claim-all"
printf '%s\n' "$post_claim_process_output" | grep -F 'a live retired Pi process blocks cleanup' >/dev/null \
    || fail "retired Pi cleanup did not explain its post-claim process refusal"
[ -f "$post_claim_process_home/.local/share/agentstart/resources/pi/owned" ] \
    || fail "retired Pi cleanup did not restore claims after a post-claim process"

final_process_home="$skip_test_dir/retired-pi-final-process-home"
final_process_trigger="$final_process_home/process-present"
final_process_hook="$final_process_home/start-process-before-final-audit"
make_retired_pi_claim_fixture "$final_process_home"
make_retired_pi_process_fixture "$final_process_home"
cat >"$final_process_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
: >"$AGENTSTART_TEST_PI_PROCESS_TRIGGER"
EOF
chmod +x "$final_process_hook"
set +e
final_process_output=$(AGENTSTART_PI_CLEANUP_HOME="$final_process_home" \
    AGENTSTART_TEST_PI_PS_BIN="$final_process_home/fake-ps" \
    AGENTSTART_TEST_PI_PROCESS_TRIGGER="$final_process_trigger" \
    AGENTSTART_TEST_PI_FINAL_HOOK="$final_process_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
final_process_status=$?
set -e
[ "$final_process_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a process started before final audit"
printf '%s\n' "$final_process_output" | grep -F 'a live retired Pi process blocks cleanup' >/dev/null \
    || fail "retired Pi cleanup did not explain its final process refusal"

# Unsafe NVM occupants and failed recursive enumeration are pre-mutation
# failures. Neither may be treated as an empty or harmless result.
nvm_symlink_home="$skip_test_dir/retired-pi-nvm-symlink-home"
mkdir -p "$nvm_symlink_home/.nvm/versions/node" "$nvm_symlink_home/nvm-target" \
    "$nvm_symlink_home/.pi"
ln -s "$nvm_symlink_home/nvm-target" \
    "$nvm_symlink_home/.nvm/versions/node/v99.0.0"
set +e
nvm_symlink_output=$(AGENTSTART_PI_CLEANUP_HOME="$nvm_symlink_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
nvm_symlink_status=$?
set -e
[ "$nvm_symlink_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a symlink NVM version occupant"
printf '%s\n' "$nvm_symlink_output" \
    | grep -F 'refusing unsafe NVM version-root occupant' >/dev/null \
    || fail "retired Pi cleanup did not explain its NVM symlink refusal"
[ -d "$nvm_symlink_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after an unsafe NVM occupant"

failed_find_home="$skip_test_dir/retired-pi-failed-find-home"
failed_find_bin="$failed_find_home/failing-find"
mkdir -p "$failed_find_home/.pi/agent/sessions"
cat >"$failed_find_bin" <<'EOF'
#!/bin/bash
exit 73
EOF
chmod +x "$failed_find_bin"
set +e
failed_find_output=$(AGENTSTART_PI_CLEANUP_HOME="$failed_find_home" \
    AGENTSTART_TEST_PI_FIND_BIN="$failed_find_bin" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
failed_find_status=$?
set -e
[ "$failed_find_status" -ne 0 ] \
    || fail "retired Pi cleanup treated failed find enumeration as empty"
printf '%s\n' "$failed_find_output" | grep -F 'could not enumerate' >/dev/null \
    || fail "retired Pi cleanup did not explain its find failure"
[ -d "$failed_find_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after failed find enumeration"

# Shared redaction files must have one public hard-link name. An external name
# makes in-place redaction ambiguous and blocks dedicated-state deletion.
hardlinked_jsonl_home="$skip_test_dir/retired-pi-hardlinked-jsonl-home"
hardlinked_jsonl="$hardlinked_jsonl_home/.local/state/agentlaunch/submitted.jsonl"
mkdir -p "$(dirname "$hardlinked_jsonl")" "$hardlinked_jsonl_home/.pi"
install_retired_pi_agentlaunch_contract "$hardlinked_jsonl_home"
printf '%s\n' '{"at":"2026-08-31T00:00:00Z","project":"hardlink","harness":"pi","model":"model","effort":"high","worktree":false,"priming":null,"focus":true}' \
    >"$hardlinked_jsonl"
ln "$hardlinked_jsonl" "$hardlinked_jsonl_home/second-jsonl-name"
set +e
hardlinked_jsonl_output=$(AGENTSTART_PI_CLEANUP_HOME="$hardlinked_jsonl_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
hardlinked_jsonl_status=$?
set -e
[ "$hardlinked_jsonl_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a hard-linked shared JSONL"
printf '%s\n' "$hardlinked_jsonl_output" \
    | grep -F 'has another hard-link name' >/dev/null \
    || fail "retired Pi cleanup did not explain its shared JSONL hard-link refusal"
[ -d "$hardlinked_jsonl_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after a shared JSONL hard link"

hardlinked_herdr_home="$skip_test_dir/retired-pi-hardlinked-herdr-home"
hardlinked_herdr="$hardlinked_herdr_home/.local/state/herdr/agent-detection/status.toml"
mkdir -p "$(dirname "$hardlinked_herdr")" "$hardlinked_herdr_home/.pi"
cat >"$hardlinked_herdr" <<'EOF'
[agents.pi]
cached_version = "fixture"
last_checked_unix = 1
last_result = "current"
EOF
ln "$hardlinked_herdr" "$hardlinked_herdr_home/second-herdr-name"
set +e
hardlinked_herdr_output=$(AGENTSTART_PI_CLEANUP_HOME="$hardlinked_herdr_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
hardlinked_herdr_status=$?
set -e
[ "$hardlinked_herdr_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a hard-linked shared Herdr file"
printf '%s\n' "$hardlinked_herdr_output" \
    | grep -F 'has another hard-link name' >/dev/null \
    || fail "retired Pi cleanup did not explain its Herdr hard-link refusal"
[ -d "$hardlinked_herdr_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after a Herdr hard link"

# Reopening the public name after every in-place write must traverse the
# currently named parents, not a descriptor chain captured before a parent
# replacement. Neither the old inode nor the foreign replacement may be
# edited when a producer directory is swapped during redaction.
parent_swapped_jsonl_home="$skip_test_dir/retired-pi-parent-swapped-jsonl-home"
parent_swapped_jsonl="$parent_swapped_jsonl_home/.local/state/agentlaunch/submitted.jsonl"
parent_swapped_jsonl_hook="$parent_swapped_jsonl_home/swap-jsonl-parent"
mkdir -p "$(dirname "$parent_swapped_jsonl")" "$parent_swapped_jsonl_home/.pi"
install_retired_pi_agentlaunch_contract "$parent_swapped_jsonl_home"
cat >"$parent_swapped_jsonl" <<'EOF'
{"at":"2026-08-31T00:00:00Z","project":"original","harness":"pi","model":"model","effort":"high","worktree":false,"priming":null,"focus":true}
EOF
cat >"$parent_swapped_jsonl_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
path=$1
parent=${path%/*}
[ ! -e "$parent.original" ] || exit 0
mv -- "$parent" "$parent.original"
mkdir -- "$parent"
cat >"$path" <<'JSON'
{"at":"2026-08-31T00:00:01Z","project":"replacement","harness":"codex","model":"gpt","effort":"high","worktree":false,"priming":null,"focus":false}
JSON
EOF
chmod +x "$parent_swapped_jsonl_hook"
set +e
parent_swapped_jsonl_output=$(AGENTSTART_PI_CLEANUP_HOME="$parent_swapped_jsonl_home" \
    AGENTSTART_TEST_PI_JSONL_REDACT_HOOK="$parent_swapped_jsonl_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
parent_swapped_jsonl_status=$?
set -e
[ "$parent_swapped_jsonl_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a JSONL parent replacement"
printf '%s\n' "$parent_swapped_jsonl_output" \
    | grep -F 'changed path identity' >/dev/null \
    || fail "retired Pi cleanup did not explain its JSONL parent refusal"
grep -F '"project":"replacement"' "$parent_swapped_jsonl" >/dev/null \
    && grep -F '"project":"original"' \
        "${parent_swapped_jsonl%/*}.original/submitted.jsonl" >/dev/null \
    && [ -d "$parent_swapped_jsonl_home/.pi" ] \
    || fail "retired Pi cleanup mutated state during a JSONL parent replacement"

parent_swapped_herdr_home="$skip_test_dir/retired-pi-parent-swapped-herdr-home"
parent_swapped_herdr="$parent_swapped_herdr_home/.local/state/herdr/agent-detection/status.toml"
parent_swapped_herdr_hook="$parent_swapped_herdr_home/swap-herdr-parent"
mkdir -p "$(dirname "$parent_swapped_herdr")" "$parent_swapped_herdr_home/.pi"
cat >"$parent_swapped_herdr" <<'EOF'
[agents.pi]
cached_version = "original"
last_checked_unix = 1
last_result = "current"
EOF
cat >"$parent_swapped_herdr_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
path=$1
parent=${path%/*}
[ ! -e "$parent.original" ] || exit 0
mv -- "$parent" "$parent.original"
mkdir -- "$parent"
cat >"$path" <<'TOML'
[agents.codex]
cached_version = "replacement"
last_checked_unix = 2
last_result = "current"
TOML
EOF
chmod +x "$parent_swapped_herdr_hook"
set +e
parent_swapped_herdr_output=$(AGENTSTART_PI_CLEANUP_HOME="$parent_swapped_herdr_home" \
    AGENTSTART_TEST_PI_HERDR_REDACT_HOOK="$parent_swapped_herdr_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
parent_swapped_herdr_status=$?
set -e
[ "$parent_swapped_herdr_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a Herdr parent replacement"
printf '%s\n' "$parent_swapped_herdr_output" \
    | grep -F 'changed while its descriptor was active' >/dev/null \
    || fail "retired Pi cleanup did not explain its Herdr parent refusal"
grep -F 'cached_version = "replacement"' "$parent_swapped_herdr" >/dev/null \
    && grep -F 'cached_version = "original"' \
        "${parent_swapped_herdr%/*}.original/status.toml" >/dev/null \
    && [ -d "$parent_swapped_herdr_home/.pi" ] \
    || fail "retired Pi cleanup mutated state during a Herdr parent replacement"

# npm cache enumeration is an authorization input. Failures, overlong keys,
# and even trailing blank lines beyond the count bound fail before claims.
# A key that another writer removes after enumeration is accepted only after
# a fresh successful enumeration proves that exact key absent.
failed_npm_home="$skip_test_dir/retired-pi-failed-npm-home"
failed_npm_bin="$failed_npm_home/failing-npm"
mkdir -p "$failed_npm_home/.npm/_cacache" "$failed_npm_home/.pi"
cat >"$failed_npm_bin" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-} ${2:-}" = 'cache ls' ] || exit 64
exit 73
EOF
chmod +x "$failed_npm_bin"
set +e
failed_npm_output=$(AGENTSTART_PI_CLEANUP_HOME="$failed_npm_home" \
    AGENTSTART_PI_CLEANUP_NPM_BIN="$failed_npm_bin" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
failed_npm_status=$?
set -e
[ "$failed_npm_status" -ne 0 ] \
    || fail "retired Pi cleanup treated failed npm enumeration as empty"
printf '%s\n' "$failed_npm_output" \
    | grep -F 'npm cache enumeration failed' >/dev/null \
    || fail "retired Pi cleanup did not explain its npm enumeration failure"
[ -d "$failed_npm_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after failed npm enumeration"

overlong_npm_home="$skip_test_dir/retired-pi-overlong-npm-home"
overlong_npm_bin="$overlong_npm_home/fake-npm"
overlong_npm_keys="$overlong_npm_home/npm-cache-keys"
mkdir -p "$overlong_npm_home/.npm/_cacache" "$overlong_npm_home/.pi"
printf '%04097d\n' 0 >"$overlong_npm_keys"
cat >"$overlong_npm_bin" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-} ${2:-}" = 'cache ls' ] || exit 64
cat "$AGENTSTART_PI_CLEANUP_NPM_KEYS"
EOF
chmod +x "$overlong_npm_bin"
set +e
overlong_npm_output=$(AGENTSTART_PI_CLEANUP_HOME="$overlong_npm_home" \
    AGENTSTART_PI_CLEANUP_NPM_BIN="$overlong_npm_bin" \
    AGENTSTART_PI_CLEANUP_NPM_KEYS="$overlong_npm_keys" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
overlong_npm_status=$?
set -e
[ "$overlong_npm_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted an overlong npm cache key"
printf '%s\n' "$overlong_npm_output" | grep -F 'overlong key' >/dev/null \
    || fail "retired Pi cleanup did not explain its overlong npm key refusal"
[ -d "$overlong_npm_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after an overlong npm key"

blank_npm_home="$skip_test_dir/retired-pi-blank-count-npm-home"
blank_npm_bin="$blank_npm_home/fake-npm"
blank_npm_keys="$blank_npm_home/npm-cache-keys"
mkdir -p "$blank_npm_home/.npm/_cacache" "$blank_npm_home/.pi"
/usr/bin/awk 'BEGIN { for (i = 0; i < 65537; i += 1) print "" }' \
    >"$blank_npm_keys"
cat >"$blank_npm_bin" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-} ${2:-}" = 'cache ls' ] || exit 64
cat "$AGENTSTART_PI_CLEANUP_NPM_KEYS"
EOF
chmod +x "$blank_npm_bin"
set +e
blank_npm_output=$(AGENTSTART_PI_CLEANUP_HOME="$blank_npm_home" \
    AGENTSTART_PI_CLEANUP_NPM_BIN="$blank_npm_bin" \
    AGENTSTART_PI_CLEANUP_NPM_KEYS="$blank_npm_keys" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
blank_npm_status=$?
set -e
[ "$blank_npm_status" -ne 0 ] \
    || fail "retired Pi cleanup dropped trailing blank npm cache lines"
printf '%s\n' "$blank_npm_output" | grep -F 'line-count bound' >/dev/null \
    || fail "retired Pi cleanup did not explain its npm line-count refusal"
[ -d "$blank_npm_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after excess blank npm lines"

vanished_npm_home="$skip_test_dir/retired-pi-vanished-npm-key-home"
vanished_npm_bin="$vanished_npm_home/fake-npm"
vanished_npm_keys="$vanished_npm_home/npm-cache-keys"
mkdir -p "$vanished_npm_home/.npm/_cacache" "$vanished_npm_home/.pi"
printf '%s\n' \
    'make-fetch-happen:request-cache:https://registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-2.23.0.tgz' \
    >"$vanished_npm_keys"
cat >"$vanished_npm_bin" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-} ${2:-}" in
    'cache ls') cat "$AGENTSTART_PI_CLEANUP_NPM_KEYS" ;;
    'cache clean')
        : >"$AGENTSTART_PI_CLEANUP_NPM_KEYS"
        exit 75
        ;;
    *) exit 64 ;;
esac
EOF
chmod +x "$vanished_npm_bin"
AGENTSTART_PI_CLEANUP_HOME="$vanished_npm_home" \
    AGENTSTART_PI_CLEANUP_NPM_BIN="$vanished_npm_bin" \
    AGENTSTART_PI_CLEANUP_NPM_KEYS="$vanished_npm_keys" \
    "$root/scripts/remove-retired-pi" --install >/dev/null
[ ! -e "$vanished_npm_home/.pi" ] \
    && [ ! -L "$vanished_npm_home/.pi" ] \
    && [ ! -s "$vanished_npm_keys" ] \
    || fail "retired Pi cleanup did not re-prove a concurrently vanished npm key"

for swapped_npm_kind in root cache; do
    swapped_npm_home="$skip_test_dir/retired-pi-swapped-npm-$swapped_npm_kind-home"
    swapped_npm_bin="$swapped_npm_home/swap-npm"
    mkdir -p "$swapped_npm_home/.npm/_cacache" "$swapped_npm_home/.pi"
    cat >"$swapped_npm_bin" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "${1:-} ${2:-}" = 'cache ls' ] || exit 64
case "$AGENTSTART_TEST_PI_NPM_SWAP_KIND" in
    root)
        mv -- "$HOME/.npm" "$HOME/.npm.original"
        mkdir -p "$HOME/.npm/_cacache"
        : >"$HOME/.npm/replacement"
        ;;
    cache)
        mv -- "$HOME/.npm/_cacache" "$HOME/.npm/_cacache.original"
        mkdir -- "$HOME/.npm/_cacache"
        : >"$HOME/.npm/_cacache/replacement"
        ;;
    *) exit 64 ;;
esac
printf '%s\n' 'make-fetch-happen:request-cache:https://registry.npmjs.org/pi-subagents'
EOF
    chmod +x "$swapped_npm_bin"
    set +e
    swapped_npm_output=$(AGENTSTART_PI_CLEANUP_HOME="$swapped_npm_home" \
        AGENTSTART_PI_CLEANUP_NPM_BIN="$swapped_npm_bin" \
        AGENTSTART_TEST_PI_NPM_SWAP_KIND="$swapped_npm_kind" \
        "$root/scripts/remove-retired-pi" --install 2>&1)
    swapped_npm_status=$?
    set -e
    [ "$swapped_npm_status" -ne 0 ] \
        || fail "retired Pi cleanup accepted a swapped npm $swapped_npm_kind"
    printf '%s\n' "$swapped_npm_output" \
        | grep -F 'changed during retired cache cleanup' >/dev/null \
        || fail "retired Pi cleanup did not explain its npm $swapped_npm_kind swap refusal"
    [ -d "$swapped_npm_home/.pi" ] \
        || fail "retired Pi cleanup mutated state after an npm $swapped_npm_kind swap"
done

# The retired Pi cleanup proves every shared-state shape before mutation. It
# removes typed harness rows rather than prompt-text matches, deletes only
# AgentSurface slugs keyed by native Pi transcripts, and proves the managed
# npm/Bun/plugin/cache identities before recursive cleanup.
retired_pi_home="$skip_test_dir/retired-pi-home"
retired_pi_node="$retired_pi_home/.nvm/versions/node/v99.0.0"
retired_pi_package="$retired_pi_node/lib/node_modules/@earendil-works/pi-coding-agent"
retired_pi_transcript="$retired_pi_home/.pi/agent/sessions/project/2026-08-31T00-00-00-000Z_fixture-pi-session.jsonl"
retired_pi_slug_key=$(basename "$retired_pi_transcript" .jsonl)
retired_pi_npm="$retired_pi_home/fake-npm"
retired_pi_npm_log="$retired_pi_home/npm-clean.log"
retired_pi_npm_keys="$retired_pi_home/npm-cache-keys"
retired_pi_append_hook="$retired_pi_home/append-during-redaction"
retired_pi_herdr_hook="$retired_pi_home/append-during-herdr-redaction"
mkdir -p \
    "$retired_pi_package/dist/bundle" \
    "$retired_pi_node/bin" \
    "$(dirname "$retired_pi_transcript")" \
    "$retired_pi_home/code/pi-viewer" \
    "$retired_pi_home/.bun/bin" \
    "$retired_pi_home/.bun/install/global/node_modules" \
    "$retired_pi_home/.local/share/agentstart/pi-subagents/pi-subagents" \
    "$retired_pi_home/.local/share/agentstart/resources/pi/extensions" \
    "$retired_pi_home/.local/share/agentlaunch/shims" \
    "$retired_pi_home/.local/share/agentsurface/shims" \
    "$retired_pi_home/.local/state/agentlaunch" \
    "$retired_pi_home/.local/state/agentsurface/slugs" \
    "$retired_pi_home/.local/state/agentstart" \
    "$retired_pi_home/.local/state/herdr/agent-detection/remote" \
    "$retired_pi_home/.npm/_cacache" \
    "$retired_pi_home/.codex/plugins/cache/agentstart-managed/agent/1.0.0/.codex-plugin" \
    "$retired_pi_home/.claude/plugins/cache/agentstart-managed/agentstart-core/1.0.0/.claude-plugin"
install_retired_pi_agentlaunch_contract "$retired_pi_home"
install_retired_pi_agentsurface_contract "$retired_pi_home"
install_retired_pi_agentchats_contract "$retired_pi_home"
printf 'legacy Pi retirement lock\n' \
    >"$retired_pi_home/.local/state/agentstart/retire-pi.lock"
cat >"$retired_pi_npm" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-} ${2:-}" in
    'cache ls')
        cat "$AGENTSTART_PI_CLEANUP_NPM_KEYS"
        ;;
    'cache clean')
        [ "$#" -eq 5 ] && [ "$3" = --force ] && [ "$4" = -- ] || exit 65
        key=$5
        printf '%s\n' "$key" >>"$AGENTSTART_PI_CLEANUP_NPM_LOG"
        /usr/bin/grep -Fvx -- "$key" "$AGENTSTART_PI_CLEANUP_NPM_KEYS" \
            >"$AGENTSTART_PI_CLEANUP_NPM_KEYS.next" || true
        mv -f -- "$AGENTSTART_PI_CLEANUP_NPM_KEYS.next" \
            "$AGENTSTART_PI_CLEANUP_NPM_KEYS"
        ;;
    *)
        exit 64
        ;;
esac
EOF
chmod +x "$retired_pi_npm"
cat >"$retired_pi_npm_keys" <<'EOF'
make-fetch-happen:request-cache:https://registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-1.2.3.tgz
make-fetch-happen:request-cache:https://registry.npmjs.org/@earendil-works%2fpi-coding-agent/-/pi-coding-agent-0.1.0.tgz
make-fetch-happen:request-cache:https://registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-2.23.0.tgz
make-fetch-happen:request-cache:https://registry.npmjs.org/react/-/react-19.0.0.tgz
EOF
cat >"$retired_pi_append_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
path=$1
schema=$2
marker="$path.concurrent-append-complete"
[ ! -e "$marker" ] || exit 0
case "$schema" in
    agentlaunch)
        printf '%s\n' '{"at":"2026-08-31T00:00:02Z","project":"concurrent","harness":"codex","model":"gpt","effort":"high","worktree":false,"priming":null,"focus":false}' >>"$path"
        ;;
    agentsurface-launches)
        printf '%s\n' '{"at":"2026-08-31T00:00:02Z","project":"concurrent","harness":"claude","worktree":false,"branch":null,"workspace":"concurrent","agent":"concurrent","named":false}' >>"$path"
        ;;
    agentsurface-submitted)
        printf '%s\n' '{"at":"2026-08-31T00:00:02Z","plan":{"harness":"claude","prompt":"concurrent unrelated append"}}' >>"$path"
        ;;
    *)
        exit 64
        ;;
esac
: >"$marker"
EOF
chmod +x "$retired_pi_append_hook"
cat >"$retired_pi_herdr_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
path=$1
marker="$path.concurrent-append-complete"
[ ! -e "$marker" ] || exit 0
cat >>"$path" <<'TOML'

[agents.cursor]
cached_version = "concurrent"
last_checked_unix = 4
last_result = "current"
TOML
: >"$marker"
EOF
chmod +x "$retired_pi_herdr_hook"
cat >"$retired_pi_package/package.json" <<'EOF'
{"name":"@earendil-works/pi-coding-agent","bin":{"pi":"dist/bundle/cli.js"}}
EOF
printf '#!/bin/sh\n' >"$retired_pi_package/dist/bundle/cli.js"
ln -s '../lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js' \
    "$retired_pi_node/bin/pi"
cat >"$retired_pi_home/code/pi-viewer/README.md" <<'EOF'
# Retired

This project has been retired. Its former product, launcher, dependencies,
and source checkout are no longer maintained or distributed from this branch.
EOF
printf 'fixture license\n' >"$retired_pi_home/code/pi-viewer/LICENSE"
git -C "$retired_pi_home/code/pi-viewer" init -q -b main
git -C "$retired_pi_home/code/pi-viewer" config user.email fixture@example.invalid
git -C "$retired_pi_home/code/pi-viewer" config user.name Fixture
git -C "$retired_pi_home/code/pi-viewer" remote add origin \
    git@github.com:possibilities/pi-viewer.git
git -C "$retired_pi_home/code/pi-viewer" add LICENSE README.md
git -C "$retired_pi_home/code/pi-viewer" commit -q -m Retired
git -C "$retired_pi_home/code/pi-viewer" update-ref refs/remotes/origin/main \
    "$(git -C "$retired_pi_home/code/pi-viewer" rev-parse HEAD)"
git -C "$retired_pi_home/code/pi-viewer" config branch.main.remote origin
git -C "$retired_pi_home/code/pi-viewer" config branch.main.merge refs/heads/main
ln -s "$retired_pi_home/code/pi-viewer" \
    "$retired_pi_home/.bun/install/global/node_modules/pi-viewer"
ln -s '../install/global/node_modules/pi-viewer/bin/pi-viewer.ts' \
    "$retired_pi_home/.bun/bin/pi-viewer"
printf '#!/bin/sh\n# AgentStart-managed AgentLaunch shim: retired fixture\n' \
    >"$retired_pi_home/.local/share/agentlaunch/shims/pi"
printf '# AgentStart-managed agentsurface shim: retired fixture\n' \
    >"$retired_pi_home/.local/share/agentsurface/shims/pi"
cat >"$retired_pi_home/.codex/plugins/cache/agentstart-managed/agent/1.0.0/.codex-plugin/plugin.json" <<'EOF'
{"name":"agent","version":"1.0.0"}
EOF
cat >"$retired_pi_home/.claude/plugins/cache/agentstart-managed/agentstart-core/1.0.0/.claude-plugin/plugin.json" <<'EOF'
{"name":"agentstart-core","version":"1.0.0"}
EOF
cat >"$retired_pi_home/.local/state/agentlaunch/submitted.jsonl" <<'EOF'
{"at":"2026-08-31T00:00:00Z","project":"keep","harness":"codex","model":"gpt","effort":"high","worktree":true,"priming":null,"focus":true}
{"at":"2026-08-31T00:00:01Z","project":"remove","harness":"pi","model":"model","effort":"high","worktree":false,"priming":null,"focus":true}
EOF
cat >"$retired_pi_home/.local/state/agentlaunch/form-draft.json" <<'EOF'
{"prompt":"fixture","project":"fixture","worktree":false,"harness":"pi","model":"model","effort":"high","priming":"none"}
EOF
cat >"$retired_pi_home/.local/state/agentsurface/launches.jsonl" <<'EOF'
{"at":"2026-08-31T00:00:00Z","project":"keep","harness":"claude","worktree":false,"branch":null,"workspace":"keep","agent":"keep","named":true}
{"at":"2026-08-31T00:00:01Z","project":"remove","harness":"pi","worktree":false,"branch":null,"workspace":"remove","agent":"remove"}
EOF
cat >"$retired_pi_home/.local/state/agentsurface/submitted.jsonl" <<'EOF'
{"at":"2026-08-31T00:00:00Z","plan":{"harness":"codex","prompt":"Pi may appear in unrelated prompt text"}}
{"at":"2026-08-31T00:00:01Z","plan":{"harness":"pi","prompt":"remove"}}
EOF
printf '{"type":"session","id":"fixture-pi-session"}\n' >"$retired_pi_transcript"
printf 'retired-pi-slug\n' \
    >"$retired_pi_home/.local/state/agentsurface/slugs/$retired_pi_slug_key"
printf 'keep-unrelated-slug\n' \
    >"$retired_pi_home/.local/state/agentsurface/slugs/unrelated-session"
printf 'fixture\n' >"$retired_pi_home/.local/state/herdr/agent-detection/remote/pi.toml"
cat >"$retired_pi_home/.local/state/herdr/agent-detection/status.toml" <<'EOF'
[agents.claude]
cached_version = "1"
last_checked_unix = 1
last_result = "current"

[agents.pi]
cached_version = "2"
attempted_version = "2"
last_checked_unix = 2
last_result = "updated"

[agents.codex]
cached_version = "3"
last_checked_unix = 3
last_result = "current"
EOF
retired_pi_agentlaunch_inode=$(stat -f '%i' \
    "$retired_pi_home/.local/state/agentlaunch/submitted.jsonl")
retired_pi_launches_inode=$(stat -f '%i' \
    "$retired_pi_home/.local/state/agentsurface/launches.jsonl")
retired_pi_submitted_inode=$(stat -f '%i' \
    "$retired_pi_home/.local/state/agentsurface/submitted.jsonl")
retired_pi_herdr_inode=$(stat -f '%i' \
    "$retired_pi_home/.local/state/herdr/agent-detection/status.toml")
retired_pi_plan=$(AGENTSTART_PI_CLEANUP_HOME="$retired_pi_home" \
    "$root/scripts/remove-retired-pi" --check)
for retired_pi_plan_claim in 'pi-viewer checkout' 'typed Pi rows' 'plugin caches' 'registry cache keys'; do
    printf '%s\n' "$retired_pi_plan" | grep -F "$retired_pi_plan_claim" >/dev/null \
        || fail "retired Pi cleanup plan omits: $retired_pi_plan_claim"
done
AGENTSTART_PI_CLEANUP_HOME="$retired_pi_home" \
    AGENTSTART_PI_CLEANUP_NPM_BIN="$retired_pi_npm" \
    AGENTSTART_PI_CLEANUP_NPM_LOG="$retired_pi_npm_log" \
    AGENTSTART_PI_CLEANUP_NPM_KEYS="$retired_pi_npm_keys" \
    AGENTSTART_TEST_PI_JSONL_REDACT_HOOK="$retired_pi_append_hook" \
    AGENTSTART_TEST_PI_HERDR_REDACT_HOOK="$retired_pi_herdr_hook" \
    "$root/scripts/remove-retired-pi" --install >/dev/null
grep -F 'registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-1.2.3.tgz' \
    "$retired_pi_npm_log" >/dev/null \
    || fail "retired Pi cleanup omitted an @earendil-works/pi-* tarball cache key"
grep -F 'registry.npmjs.org/@earendil-works%2fpi-coding-agent/-/pi-coding-agent-0.1.0.tgz' \
    "$retired_pi_npm_log" >/dev/null \
    || fail "retired Pi cleanup omitted an encoded @earendil-works/pi-* cache key"
grep -F 'registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-2.23.0.tgz' \
    "$retired_pi_npm_log" >/dev/null \
    || fail "retired Pi cleanup omitted a pi-mcp-adapter cache key"
[ "$(wc -l <"$retired_pi_npm_log" | tr -d '[:space:]')" -eq 3 ] \
    || fail "retired Pi cleanup did not clean exactly one npm cache key per call"
if grep -F 'registry.npmjs.org/react/' "$retired_pi_npm_log" >/dev/null; then
    fail "retired Pi cleanup selected an unrelated npm cache key"
fi
for retired_pi_target in \
    "$retired_pi_node/bin/pi" \
    "$retired_pi_package" \
    "$retired_pi_home/.bun/bin/pi-viewer" \
    "$retired_pi_home/.bun/install/global/node_modules/pi-viewer" \
    "$retired_pi_home/code/pi-viewer" \
    "$retired_pi_home/.pi" \
    "$retired_pi_home/.local/share/agentstart/pi-subagents" \
    "$retired_pi_home/.local/share/agentstart/resources/pi" \
    "$retired_pi_home/.local/share/agentlaunch/shims/pi" \
    "$retired_pi_home/.local/share/agentsurface/shims/pi" \
    "$retired_pi_home/.claude/plugins/cache/agentstart-managed" \
    "$retired_pi_home/.local/state/agentlaunch/form-draft.json" \
    "$retired_pi_home/.local/state/agentsurface/slugs/$retired_pi_slug_key" \
    "$retired_pi_home/.local/state/agentstart/retire-pi.lock" \
    "$retired_pi_home/.local/state/herdr/agent-detection/remote/pi.toml"; do
    [ ! -e "$retired_pi_target" ] && [ ! -L "$retired_pi_target" ] \
        || fail "retired Pi cleanup left an exact managed target: $retired_pi_target"
done
[ -f "$retired_pi_home/.codex/plugins/cache/agentstart-managed/agent/1.0.0/.codex-plugin/plugin.json" ] \
    || fail "retired Pi cleanup removed the refreshed Pi-free Codex plugin cache"
for retired_pi_log in \
    "$retired_pi_home/.local/state/agentlaunch/submitted.jsonl" \
    "$retired_pi_home/.local/state/agentsurface/launches.jsonl"; do
    /usr/bin/jq -s -e '
        length == 2 and
        all(.[]; .harness != "pi") and
        ([.[] | select(.project == "concurrent")] | length == 1)
    ' "$retired_pi_log" >/dev/null \
        || fail "retired Pi cleanup lost or duplicated a concurrent unrelated typed log row: $retired_pi_log"
done
/usr/bin/jq -s -e '
    length == 2 and
    all(.[]; .plan.harness != "pi") and
    ([.[] | select(.plan.prompt == "concurrent unrelated append")] | length == 1)
' \
    "$retired_pi_home/.local/state/agentsurface/submitted.jsonl" >/dev/null \
    || fail "retired Pi cleanup lost or duplicated a concurrent legacy submission row"
for inode_check in \
    "$retired_pi_agentlaunch_inode:$retired_pi_home/.local/state/agentlaunch/submitted.jsonl" \
    "$retired_pi_launches_inode:$retired_pi_home/.local/state/agentsurface/launches.jsonl" \
    "$retired_pi_submitted_inode:$retired_pi_home/.local/state/agentsurface/submitted.jsonl"; do
    expected_inode=${inode_check%%:*}
    inode_path=${inode_check#*:}
    [ "$(stat -f '%i' "$inode_path")" = "$expected_inode" ] \
        || fail "retired Pi cleanup replaced a shared JSONL inode: $inode_path"
done
grep -F 'Pi may appear in unrelated prompt text' \
    "$retired_pi_home/.local/state/agentsurface/submitted.jsonl" >/dev/null \
    || fail "retired Pi cleanup matched prompt text instead of the typed harness"
[ -f "$retired_pi_home/.local/state/agentsurface/slugs/unrelated-session" ] \
    || fail "retired Pi cleanup removed an unrelated AgentSurface slug"
if grep -F '[agents.pi]' "$retired_pi_home/.local/state/herdr/agent-detection/status.toml" >/dev/null; then
    fail "retired Pi cleanup left Herdr's typed Pi cache block"
fi
for kept_herdr_agent in claude codex; do
    grep -F "[agents.$kept_herdr_agent]" \
        "$retired_pi_home/.local/state/herdr/agent-detection/status.toml" >/dev/null \
        || fail "retired Pi cleanup removed Herdr's $kept_herdr_agent cache block"
done
grep -F '[agents.cursor]' \
    "$retired_pi_home/.local/state/herdr/agent-detection/status.toml" >/dev/null \
    || fail "retired Pi cleanup lost a concurrent Herdr cache append"
[ "$(stat -f '%i' "$retired_pi_home/.local/state/herdr/agent-detection/status.toml")" = \
    "$retired_pi_herdr_inode" ] \
    || fail "retired Pi cleanup replaced Herdr's shared status inode"

# The retired pi-viewer branch deliberately deleted its package manifest.
# Bun's links are claimed before the canonical checkout, whose exact tracked
# tombstone, origin, clean main branch, and single-worktree topology prove that
# the whole checkout is retirement-owned.
retired_pi_viewer_home="$skip_test_dir/retired-pi-viewer-home"
mkdir -p \
    "$retired_pi_viewer_home/code/pi-viewer" \
    "$retired_pi_viewer_home/.bun/bin" \
    "$retired_pi_viewer_home/.bun/install/global/node_modules"
cat >"$retired_pi_viewer_home/code/pi-viewer/README.md" <<'EOF'
# Retired

This project has been retired. Its former product, launcher, dependencies,
and source checkout are no longer maintained or distributed from this branch.
EOF
printf 'fixture license\n' >"$retired_pi_viewer_home/code/pi-viewer/LICENSE"
git -C "$retired_pi_viewer_home/code/pi-viewer" init -q -b main
git -C "$retired_pi_viewer_home/code/pi-viewer" config user.email fixture@example.invalid
git -C "$retired_pi_viewer_home/code/pi-viewer" config user.name Fixture
git -C "$retired_pi_viewer_home/code/pi-viewer" remote add origin \
    git@github.com:possibilities/pi-viewer.git
git -C "$retired_pi_viewer_home/code/pi-viewer" add LICENSE README.md
git -C "$retired_pi_viewer_home/code/pi-viewer" commit -q -m Retired
git -C "$retired_pi_viewer_home/code/pi-viewer" update-ref refs/remotes/origin/main \
    "$(git -C "$retired_pi_viewer_home/code/pi-viewer" rev-parse HEAD)"
git -C "$retired_pi_viewer_home/code/pi-viewer" config branch.main.remote origin
git -C "$retired_pi_viewer_home/code/pi-viewer" config branch.main.merge refs/heads/main
ln -s "$retired_pi_viewer_home/code/pi-viewer" \
    "$retired_pi_viewer_home/.bun/install/global/node_modules/pi-viewer"
ln -s '../install/global/node_modules/pi-viewer/bin/pi-viewer.ts' \
    "$retired_pi_viewer_home/.bun/bin/pi-viewer"
AGENTSTART_PI_CLEANUP_HOME="$retired_pi_viewer_home" \
    "$root/scripts/remove-retired-pi" --install >/dev/null
[ ! -e "$retired_pi_viewer_home/.bun/bin/pi-viewer" ] \
    && [ ! -L "$retired_pi_viewer_home/.bun/bin/pi-viewer" ] \
    || fail "retired Pi cleanup left the tombstoned pi-viewer launcher"
[ ! -e "$retired_pi_viewer_home/.bun/install/global/node_modules/pi-viewer" ] \
    && [ ! -L "$retired_pi_viewer_home/.bun/install/global/node_modules/pi-viewer" ] \
    || fail "retired Pi cleanup left the tombstoned pi-viewer package link"
[ ! -e "$retired_pi_viewer_home/code/pi-viewer" ] \
    || fail "retired Pi cleanup left the canonical pi-viewer checkout"

# The historical viewer sometimes carried the Pi source as an untracked Git
# module after .gitmodules was removed on the tombstone branch. Its one exact
# owned topology is safe to delete together; every other worktree, ref, ignored
# file, unpublished commit, or non-GitHub origin must block checkout deletion.
nested_retired_pi_viewer_home="$skip_test_dir/nested-retired-pi-viewer-home"
mkdir -p "$nested_retired_pi_viewer_home"
nested_retired_pi_viewer_home=$(cd -P -- "$nested_retired_pi_viewer_home" && pwd)
nested_retired_pi_viewer="$nested_retired_pi_viewer_home/code/pi-viewer"
nested_retired_pi="$nested_retired_pi_viewer/pi"
make_retired_pi_viewer_checkout "$nested_retired_pi_viewer_home"
mkdir -p "$nested_retired_pi"
git -C "$nested_retired_pi" init -q -b pi-viewer
git -C "$nested_retired_pi" config user.email fixture@example.invalid
git -C "$nested_retired_pi" config user.name Fixture
git -C "$nested_retired_pi" remote add origin git@github.com:possibilities/pi.git
printf 'nested fixture\n' >"$nested_retired_pi/README.md"
printf 'node_modules/\n' >"$nested_retired_pi/.gitignore"
git -C "$nested_retired_pi" add .gitignore README.md
git -C "$nested_retired_pi" commit -q -m 'Retired nested Pi fixture'
nested_retired_pi_head=$(git -C "$nested_retired_pi" rev-parse HEAD)
git -C "$nested_retired_pi" update-ref refs/remotes/origin/pi-viewer \
    "$nested_retired_pi_head"
git -C "$nested_retired_pi" update-ref refs/heads/main \
    "$nested_retired_pi_head"
git -C "$nested_retired_pi" update-ref refs/remotes/origin/main \
    "$nested_retired_pi_head"
git -C "$nested_retired_pi" config branch.pi-viewer.remote origin
git -C "$nested_retired_pi" config branch.pi-viewer.merge refs/heads/pi-viewer
mkdir -p \
    "$nested_retired_pi/node_modules/package" \
    "$nested_retired_pi/packages/agent/node_modules/package"
printf 'ignored root package\n' \
    >"$nested_retired_pi/node_modules/package/index.js"
printf 'ignored workspace package\n' \
    >"$nested_retired_pi/packages/agent/node_modules/package/index.js"
mkdir -p "$nested_retired_pi_viewer/.git/modules"
mv -- "$nested_retired_pi/.git" "$nested_retired_pi_viewer/.git/modules/pi"
printf '%s\n' 'gitdir: ../.git/modules/pi' >"$nested_retired_pi/.git"
git -C "$nested_retired_pi_viewer" config submodule.pi.url \
    git@github.com:possibilities/pi.git
git -C "$nested_retired_pi_viewer" config submodule.pi.active true
nested_foreign_pi_viewer_home="$skip_test_dir/nested-foreign-retired-pi-viewer-home"
cp -R -- "$nested_retired_pi_viewer_home" "$nested_foreign_pi_viewer_home"
nested_foreign_pi_viewer_home=$(cd -P -- "$nested_foreign_pi_viewer_home" && pwd)
nested_foreign_pi_viewer="$nested_foreign_pi_viewer_home/code/pi-viewer"
printf '%s\n' private-notes \
    >>"$nested_foreign_pi_viewer/.git/modules/pi/info/exclude"
printf 'independent ignored state\n' \
    >"$nested_foreign_pi_viewer/pi/private-notes"
mkdir -p "$nested_foreign_pi_viewer_home/.pi"
AGENTSTART_PI_CLEANUP_HOME="$nested_retired_pi_viewer_home" \
    "$root/scripts/remove-retired-pi" --install >/dev/null
[ ! -e "$nested_retired_pi_viewer" ] \
    || fail "retired Pi cleanup left the exact nested pi-viewer topology"
set +e
nested_foreign_pi_viewer_output=$(AGENTSTART_PI_CLEANUP_HOME="$nested_foreign_pi_viewer_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
nested_foreign_pi_viewer_status=$?
set -e
[ "$nested_foreign_pi_viewer_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted foreign ignored state in nested Pi"
printf '%s\n' "$nested_foreign_pi_viewer_output" \
    | grep -F 'foreign ignored local state: private-notes' >/dev/null \
    || fail "retired Pi cleanup did not explain foreign nested ignored state"
[ -d "$nested_foreign_pi_viewer" ] \
    && [ -d "$nested_foreign_pi_viewer_home/.pi" ] \
    || fail "retired Pi cleanup mutated foreign nested ignored state"

for retired_pi_viewer_risk in linked-worktree ignored-state local-ref unpushed local-remote; do
    risky_retired_pi_viewer_home="$skip_test_dir/retired-pi-viewer-$retired_pi_viewer_risk-home"
    risky_retired_pi_viewer="$risky_retired_pi_viewer_home/code/pi-viewer"
    make_retired_pi_viewer_checkout "$risky_retired_pi_viewer_home"
    mkdir -p "$risky_retired_pi_viewer_home/.pi"
    case "$retired_pi_viewer_risk" in
        linked-worktree)
            git -C "$risky_retired_pi_viewer" worktree add -q \
                "$risky_retired_pi_viewer_home/linked" -b linked
            risky_retired_pi_viewer_expect='still has a linked worktree'
            ;;
        ignored-state)
            printf '%s\n' ignored-local \
                >>"$risky_retired_pi_viewer/.git/info/exclude"
            : >"$risky_retired_pi_viewer/ignored-local"
            risky_retired_pi_viewer_expect='has ignored local state'
            ;;
        local-ref)
            printf 'local change\n' >>"$risky_retired_pi_viewer/README.md"
            git -C "$risky_retired_pi_viewer" stash push -q
            risky_retired_pi_viewer_expect='has a local-only Git ref'
            ;;
        unpushed)
            git -C "$risky_retired_pi_viewer" commit -q --allow-empty \
                -m 'Unpushed fixture'
            risky_retired_pi_viewer_expect='is not equal to pushed origin/main'
            ;;
        local-remote)
            git -C "$risky_retired_pi_viewer" remote set-url origin \
                "$risky_retired_pi_viewer_home/local-origin.git"
            risky_retired_pi_viewer_expect='has a foreign origin'
            ;;
        *) fail "unknown retired pi-viewer risk fixture" ;;
    esac
    set +e
    risky_retired_pi_viewer_output=$(AGENTSTART_PI_CLEANUP_HOME="$risky_retired_pi_viewer_home" \
        "$root/scripts/remove-retired-pi" --install 2>&1)
    risky_retired_pi_viewer_status=$?
    set -e
    [ "$risky_retired_pi_viewer_status" -ne 0 ] \
        || fail "retired Pi cleanup accepted pi-viewer $retired_pi_viewer_risk state"
    printf '%s\n' "$risky_retired_pi_viewer_output" \
        | grep -F "$risky_retired_pi_viewer_expect" >/dev/null \
        || fail "retired Pi cleanup did not explain pi-viewer $retired_pi_viewer_risk refusal"
    [ -d "$risky_retired_pi_viewer" ] \
        && [ -d "$risky_retired_pi_viewer_home/.pi" ] \
        || fail "retired Pi cleanup mutated pi-viewer $retired_pi_viewer_risk state"
done

bad_retired_pi_viewer_home="$skip_test_dir/bad-retired-pi-viewer-home"
mkdir -p \
    "$bad_retired_pi_viewer_home/code/pi-viewer" \
    "$bad_retired_pi_viewer_home/.bun/bin" \
    "$bad_retired_pi_viewer_home/.bun/install/global/node_modules" \
    "$bad_retired_pi_viewer_home/.pi"
printf '# Independently repurposed checkout\n' \
    >"$bad_retired_pi_viewer_home/code/pi-viewer/README.md"
ln -s "$bad_retired_pi_viewer_home/code/pi-viewer" \
    "$bad_retired_pi_viewer_home/.bun/install/global/node_modules/pi-viewer"
ln -s '../install/global/node_modules/pi-viewer/bin/pi-viewer.ts' \
    "$bad_retired_pi_viewer_home/.bun/bin/pi-viewer"
set +e
bad_retired_pi_viewer_output=$(AGENTSTART_PI_CLEANUP_HOME="$bad_retired_pi_viewer_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
bad_retired_pi_viewer_status=$?
set -e
[ "$bad_retired_pi_viewer_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a changed pi-viewer tombstone"
printf '%s\n' "$bad_retired_pi_viewer_output" \
    | grep -F 'tombstone identity mismatch' >/dev/null \
    || fail "retired Pi cleanup did not explain its pi-viewer tombstone refusal"
[ -L "$bad_retired_pi_viewer_home/.bun/bin/pi-viewer" ] \
    && [ -L "$bad_retired_pi_viewer_home/.bun/install/global/node_modules/pi-viewer" ] \
    && [ -d "$bad_retired_pi_viewer_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after refusing a changed pi-viewer tombstone"

# A second run is a no-op, and a foreign package at the retired location fails
# closed before any dedicated state is removed.
AGENTSTART_PI_CLEANUP_HOME="$retired_pi_home" \
    AGENTSTART_PI_CLEANUP_NPM_BIN="$retired_pi_npm" \
    AGENTSTART_PI_CLEANUP_NPM_LOG="$retired_pi_npm_log" \
    AGENTSTART_PI_CLEANUP_NPM_KEYS="$retired_pi_npm_keys" \
    AGENTSTART_TEST_PI_JSONL_REDACT_HOOK="$retired_pi_append_hook" \
    AGENTSTART_TEST_PI_HERDR_REDACT_HOOK="$retired_pi_herdr_hook" \
    "$root/scripts/remove-retired-pi" --install >/dev/null
bad_retired_pi_home="$skip_test_dir/bad-retired-pi-home"
bad_retired_pi_package="$bad_retired_pi_home/.nvm/versions/node/v99.0.0/lib/node_modules/@earendil-works/pi-coding-agent"
mkdir -p "$bad_retired_pi_package" "$bad_retired_pi_home/.pi"
printf '{"name":"independent-package","bin":{"pi":"cli.js"}}\n' \
    >"$bad_retired_pi_package/package.json"
set +e
bad_retired_pi_output=$(AGENTSTART_PI_CLEANUP_HOME="$bad_retired_pi_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
bad_retired_pi_status=$?
set -e
[ "$bad_retired_pi_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a foreign npm package"
printf '%s\n' "$bad_retired_pi_output" | grep -F 'identity mismatch' >/dev/null \
    || fail "retired Pi cleanup did not explain its package refusal"
[ -f "$bad_retired_pi_package/package.json" ] && [ -d "$bad_retired_pi_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after refusing package ownership"

bad_retired_state_home="$skip_test_dir/bad-retired-pi-state-home"
mkdir -p \
    "$bad_retired_state_home/.pi" \
    "$bad_retired_state_home/.local/state/agentlaunch"
install_retired_pi_agentlaunch_contract "$bad_retired_state_home"
printf '{"harness":"cursor"}\n' \
    >"$bad_retired_state_home/.local/state/agentlaunch/submitted.jsonl"
set +e
bad_retired_state_output=$(AGENTSTART_PI_CLEANUP_HOME="$bad_retired_state_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
bad_retired_state_status=$?
set -e
[ "$bad_retired_state_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a foreign typed-state row"
printf '%s\n' "$bad_retired_state_output" | grep -F 'malformed or foreign' >/dev/null \
    || fail "retired Pi cleanup did not explain its typed-state refusal"
[ -d "$bad_retired_state_home/.pi" ] \
    || fail "retired Pi cleanup mutated dedicated state after refusing a foreign log"

# A lexically in-home path is not sufficient ownership proof when one of its
# parents is a symlink. Refuse before touching either the escaped shared log or
# the dedicated native state.
escaped_retired_state_home="$skip_test_dir/escaped-retired-pi-state-home"
escaped_retired_state_target="$skip_test_dir/escaped-retired-pi-state-target"
mkdir -p \
    "$escaped_retired_state_home/.pi" \
    "$escaped_retired_state_target/state/agentlaunch"
ln -s "$escaped_retired_state_target" "$escaped_retired_state_home/.local"
install_retired_pi_agentlaunch_contract "$escaped_retired_state_home"
cat >"$escaped_retired_state_target/state/agentlaunch/submitted.jsonl" <<'EOF'
{"at":"2026-08-31T00:00:00Z","project":"escaped","harness":"pi","model":"model","effort":"high","worktree":false,"priming":null,"focus":true}
EOF
set +e
escaped_retired_state_output=$(AGENTSTART_PI_CLEANUP_HOME="$escaped_retired_state_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
escaped_retired_state_status=$?
set -e
[ "$escaped_retired_state_status" -ne 0 ] \
    || fail "retired Pi cleanup followed an escaping state parent"
printf '%s\n' "$escaped_retired_state_output" \
    | grep -F 'could not create or prove retirement state directory' >/dev/null \
    || fail "retired Pi cleanup did not explain its escaping-parent refusal"
[ -f "$escaped_retired_state_target/state/agentlaunch/submitted.jsonl" ] \
    && [ -d "$escaped_retired_state_home/.pi" ] \
    || fail "retired Pi cleanup mutated state after refusing an escaping parent"

bad_retired_status_home="$skip_test_dir/bad-retired-pi-status-home"
mkdir -p \
    "$bad_retired_status_home/.pi" \
    "$bad_retired_status_home/.local/state/herdr/agent-detection"
cat >"$bad_retired_status_home/.local/state/herdr/agent-detection/status.toml" <<'EOF'
[agents.pi]
cached_version = "fixture"
foreign_key = "do not discard"
EOF
set +e
bad_retired_status_output=$(AGENTSTART_PI_CLEANUP_HOME="$bad_retired_status_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
bad_retired_status_status=$?
set -e
[ "$bad_retired_status_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a changed Herdr cache block"
printf '%s\n' "$bad_retired_status_output" | grep -F 'changed [agents.pi]' >/dev/null \
    || fail "retired Pi cleanup did not explain its Herdr cache refusal"
[ -d "$bad_retired_status_home/.pi" ] \
    || fail "retired Pi cleanup mutated dedicated state after refusing a Herdr cache block"

# JSONL validation, selection, overwrite, and fsync share one no-follow file
# descriptor. Replacing the public path from the concurrency hook must make the
# cleanup fail without applying the old offsets to the replacement file.
swapped_retired_jsonl_home="$skip_test_dir/swapped-retired-pi-jsonl-home"
swapped_retired_jsonl="$swapped_retired_jsonl_home/.local/state/agentlaunch/submitted.jsonl"
swapped_retired_jsonl_hook="$swapped_retired_jsonl_home/swap-jsonl-path"
mkdir -p "$(dirname "$swapped_retired_jsonl")" "$swapped_retired_jsonl_home/.pi"
install_retired_pi_agentlaunch_contract "$swapped_retired_jsonl_home"
cat >"$swapped_retired_jsonl" <<'EOF'
{"at":"2026-08-31T00:00:00Z","project":"remove","harness":"pi","model":"model","effort":"high","worktree":false,"priming":null,"focus":true}
EOF
cat >"$swapped_retired_jsonl_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
path=$1
schema=$2
[ "$schema" = agentlaunch ] || exit 64
mv "$path" "$path.validated-inode"
cat >"$path" <<'JSON'
{"at":"2026-08-31T00:00:01Z","project":"replacement","harness":"codex","model":"gpt","effort":"high","worktree":false,"priming":null,"focus":false}
JSON
EOF
chmod +x "$swapped_retired_jsonl_hook"
set +e
swapped_retired_jsonl_output=$(AGENTSTART_PI_CLEANUP_HOME="$swapped_retired_jsonl_home" \
    AGENTSTART_TEST_PI_JSONL_REDACT_HOOK="$swapped_retired_jsonl_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
swapped_retired_jsonl_status=$?
set -e
[ "$swapped_retired_jsonl_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a JSONL path replacement"
printf '%s\n' "$swapped_retired_jsonl_output" | grep -F 'changed path identity' >/dev/null \
    || fail "retired Pi cleanup did not explain its JSONL identity refusal"
jq -e '.harness == "codex" and .project == "replacement"' \
    "$swapped_retired_jsonl" >/dev/null \
    || fail "retired Pi cleanup applied stale offsets to a replacement JSONL file"
[ -d "$swapped_retired_jsonl_home/.pi" ] \
    || fail "retired Pi cleanup removed dedicated state after a JSONL path replacement"

# A target swapped after its final public-name stat is refused by the anchored
# exclusive claim move before the foreign replacement can be claimed or
# recursively removed. The empty quarantine is removed on that refusal.
swapped_retired_claim_home="$skip_test_dir/swapped-retired-pi-claim-home"
swapped_retired_claim_target="$swapped_retired_claim_home/.local/share/agentstart/resources/pi"
swapped_retired_claim_hook="$swapped_retired_claim_home/swap-claim-path"
mkdir -p "$swapped_retired_claim_target" "$swapped_retired_claim_home/.pi"
printf 'validated owned bytes\n' >"$swapped_retired_claim_target/owned"
cat >"$swapped_retired_claim_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
target=$1
expected=$(/bin/realpath "$AGENTSTART_TEST_PI_CLAIM_SWAP_TARGET")
[ "$target" = "$expected" ] || exit 0
mv "$target" "$target.validated-inode"
mkdir "$target"
printf 'foreign bytes\n' >"$target/foreign"
EOF
chmod +x "$swapped_retired_claim_hook"
set +e
swapped_retired_claim_output=$(AGENTSTART_PI_CLEANUP_HOME="$swapped_retired_claim_home" \
    AGENTSTART_TEST_PI_CLAIM_HOOK="$swapped_retired_claim_hook" \
    AGENTSTART_TEST_PI_CLAIM_SWAP_TARGET="$swapped_retired_claim_target" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
swapped_retired_claim_status=$?
set -e
[ "$swapped_retired_claim_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a post-validation target replacement"
printf '%s\n' "$swapped_retired_claim_output" \
    | grep -F 'claim move source identity changed' >/dev/null \
    || fail "retired Pi cleanup did not explain its anchored claim refusal"
[ -f "$swapped_retired_claim_target/foreign" ] \
    && [ -f "$swapped_retired_claim_target.validated-inode/owned" ] \
    && [ -d "$swapped_retired_claim_home/.pi" ] \
    || fail "retired Pi cleanup deleted state during a post-validation path swap"
[ ! -e "$swapped_retired_claim_home/.local/state/agentstart/retirement-quarantine" ] \
    || fail "retired Pi cleanup left an empty quarantine after restoring a swapped target"

# AgentSurface stores only a basename-keyed slug, so a matching transcript in
# either remaining native store makes ownership ambiguous and must block the
# deletion before the native Pi tree is touched.
colliding_retired_slug_home="$skip_test_dir/colliding-retired-pi-slug-home"
colliding_retired_slug_name='2026-08-31T00-00-00-000Z_collision-session.jsonl'
colliding_retired_slug_key=${colliding_retired_slug_name%.jsonl}
colliding_retired_transcript="$colliding_retired_slug_home/.pi/agent/sessions/project/$colliding_retired_slug_name"
colliding_active_transcript="$colliding_retired_slug_home/.claude/projects/project/$colliding_retired_slug_name"
colliding_retired_slug="$colliding_retired_slug_home/.local/state/agentsurface/slugs/$colliding_retired_slug_key"
mkdir -p \
    "$(dirname "$colliding_retired_transcript")" \
    "$(dirname "$colliding_active_transcript")" \
    "$(dirname "$colliding_retired_slug")"
install_retired_pi_agentsurface_contract "$colliding_retired_slug_home"
printf '%s\n' '{"type":"session","id":"collision-session"}' >"$colliding_retired_transcript"
printf '%s\n' '{"type":"active"}' >"$colliding_active_transcript"
printf 'collision-slug\n' >"$colliding_retired_slug"
set +e
colliding_retired_slug_output=$(AGENTSTART_PI_CLEANUP_HOME="$colliding_retired_slug_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
colliding_retired_slug_status=$?
set -e
[ "$colliding_retired_slug_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a cross-harness AgentSurface slug collision"
printf '%s\n' "$colliding_retired_slug_output" \
    | grep -F 'slug key collides with an active harness transcript' >/dev/null \
    || fail "retired Pi cleanup did not explain its AgentSurface slug collision refusal"
[ -f "$colliding_retired_slug" ] && [ -d "$colliding_retired_slug_home/.pi" ] \
    || fail "retired Pi cleanup removed an ambiguously keyed AgentSurface slug"

# A stale receipt is restore-only. After a crash leaves a valid package in the
# quarantine, changing that same preserved inode must restore it and make the
# ordinary package validator refuse it; the receipt cannot authorize deletion.
stale_retired_claim_home="$skip_test_dir/stale-retired-pi-claim-home"
stale_retired_claim_package="$stale_retired_claim_home/.nvm/versions/node/v99.0.0/lib/node_modules/@earendil-works/pi-coding-agent"
stale_retired_claim_root="$stale_retired_claim_home/.local/state/agentstart/retirement-quarantine"
mkdir -p "$stale_retired_claim_package"
printf '%s\n' '{"name":"@earendil-works/pi-coding-agent","bin":{"pi":"cli.js"}}' \
    >"$stale_retired_claim_package/package.json"
printf '#!/bin/sh\n' >"$stale_retired_claim_package/cli.js"
set +e
AGENTSTART_PI_CLEANUP_HOME="$stale_retired_claim_home" \
    AGENTSTART_TEST_PI_CRASH_AT=claim-item-renamed \
    "$root/scripts/remove-retired-pi" --install >/dev/null 2>&1
stale_retired_claim_crash_status=$?
set -e
[ "$stale_retired_claim_crash_status" -ne 0 ] \
    && [ -d "$stale_retired_claim_root" ] \
    || fail "retired Pi cleanup did not leave the expected crash receipt"
stale_retired_claim_item=$(/usr/bin/find "$stale_retired_claim_root" \
    -path '*/item' -type d -print -quit)
[ -n "$stale_retired_claim_item" ] \
    || fail "retired Pi cleanup crash did not preserve the claimed package"
printf '%s\n' '{"name":"independent-package","bin":{"pi":"cli.js"}}' \
    >"$stale_retired_claim_item/package.json"
set +e
stale_retired_claim_output=$(AGENTSTART_PI_CLEANUP_HOME="$stale_retired_claim_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
stale_retired_claim_status=$?
set -e
[ "$stale_retired_claim_status" -ne 0 ] \
    || fail "retired Pi cleanup treated a stale receipt as deletion authority"
printf '%s\n' "$stale_retired_claim_output" | grep -F 'identity mismatch' >/dev/null \
    || fail "retired Pi cleanup did not ordinarily revalidate the restored stale claim"
if [ ! -f "$stale_retired_claim_package/package.json" ] \
    || ! grep -F 'independent-package' \
        "$stale_retired_claim_package/package.json" >/dev/null; then
    fail "retired Pi cleanup deleted or failed to restore a changed stale claim"
fi
[ ! -e "$stale_retired_claim_root" ] \
    || fail "retired Pi cleanup left its quarantine after restoring a stale claim"

# Every published durability boundary must recover without treating a receipt
# as deletion authority. A one-target fixture reaches every boundary while
# keeping the recovery proof small enough to run as a matrix.
run_retired_pi_crash_boundary() {
    local fixture_home="$1"
    local boundary="$2"
    set +e
    (
        AGENTSTART_PI_CLEANUP_HOME="$fixture_home" \
            AGENTSTART_TEST_PI_CRASH_AT="$boundary" \
            "$root/scripts/remove-retired-pi" --install
    ) >/dev/null 2>&1
    retired_pi_crash_status=$?
    set -e
}

for retired_pi_crash_boundary in \
    lock-acquired \
    quarantine-temporary-created \
    quarantine-owner-temporary-durable \
    quarantine-owner-published \
    quarantine-root-published \
    claim-temporary-created \
    receipt-prepared-temporary-durable \
    receipt-prepared-published \
    claim-published \
    claim-item-renamed \
    claim-item-revalidated \
    all-claims-collected \
    all-claims-revalidated \
    pre-mutation-claims-revalidated \
    receipt-deleting-temporary-durable \
    receipt-deleting-published \
    claim-item-removed \
    receipt-deleted-temporary-durable \
    receipt-deleted-published \
    claim-receipt-removed \
    claim-directory-removed \
    quarantine-owner-removed \
    quarantine-root-removed; do
    retired_pi_crash_home="$skip_test_dir/retired-pi-crash-$retired_pi_crash_boundary"
    retired_pi_crash_target="$retired_pi_crash_home/.local/share/agentstart/resources/pi"
    make_retired_pi_claim_fixture "$retired_pi_crash_home"
    run_retired_pi_crash_boundary \
        "$retired_pi_crash_home" "$retired_pi_crash_boundary"
    [ "$retired_pi_crash_status" -eq 137 ] \
        || fail "retired Pi crash boundary was not reached: $retired_pi_crash_boundary"
    AGENTSTART_PI_CLEANUP_HOME="$retired_pi_crash_home" \
        "$root/scripts/remove-retired-pi" --install >/dev/null
    [ ! -e "$retired_pi_crash_target" ] \
        || fail "retired Pi crash recovery did not revalidate and remove: $retired_pi_crash_boundary"
    [ ! -e "$retired_pi_crash_home/.local/state/agentstart/retirement-quarantine" ] \
        || fail "retired Pi crash recovery left its quarantine: $retired_pi_crash_boundary"
done

# Receipt target ids are a closed vocabulary. Even a shape-valid receipt may
# not authorize restoring or deleting an arbitrary same-user path.
unknown_retired_receipt_home="$skip_test_dir/unknown-retired-pi-receipt-home"
unknown_retired_receipt_root="$unknown_retired_receipt_home/.local/state/agentstart/retirement-quarantine"
unknown_retired_receipt_entry="$unknown_retired_receipt_root/claim.unknown"
mkdir -p "$unknown_retired_receipt_entry/item"
printf '%s\n' 'agentstart-retirement-quarantine-v2' \
    >"$unknown_retired_receipt_root/.owner"
printf 'preserve unknown claim\n' >"$unknown_retired_receipt_entry/item/owned"
cat >"$unknown_retired_receipt_entry/receipt.json" <<EOF
{"version":2,"target_id":"unknown-target","target":"$unknown_retired_receipt_home/foreign","identity":"1:2","proof":"0000000000000000000000000000000000000000000000000000000000000000","state":"prepared"}
EOF
chmod 600 "$unknown_retired_receipt_root/.owner" \
    "$unknown_retired_receipt_entry/receipt.json"
set +e
unknown_retired_receipt_output=$(AGENTSTART_PI_CLEANUP_HOME="$unknown_retired_receipt_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
unknown_retired_receipt_status=$?
set -e
[ "$unknown_retired_receipt_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted an unknown receipt target id"
printf '%s\n' "$unknown_retired_receipt_output" \
    | grep -F 'receipt names an unknown target' >/dev/null \
    || fail "retired Pi cleanup did not explain its unknown-receipt refusal"
[ -f "$unknown_retired_receipt_entry/item/owned" ] \
    || fail "retired Pi cleanup mutated an unknown receipt item"

# Recursive ownership proof rejects a hard link whose other name escapes the
# retirement target, even though both names belong to the same user.
hardlinked_retired_pi_home="$skip_test_dir/hardlinked-retired-pi-home"
hardlinked_retired_pi_target="$hardlinked_retired_pi_home/.local/share/agentstart/resources/pi"
make_retired_pi_claim_fixture "$hardlinked_retired_pi_home"
ln "$hardlinked_retired_pi_target/owned" \
    "$hardlinked_retired_pi_home/escaped-hard-link"
set +e
hardlinked_retired_pi_output=$(AGENTSTART_PI_CLEANUP_HOME="$hardlinked_retired_pi_home" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
hardlinked_retired_pi_status=$?
set -e
[ "$hardlinked_retired_pi_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a hard link escaping its target"
printf '%s\n' "$hardlinked_retired_pi_output" \
    | grep -F 'hard link escapes the retirement target' >/dev/null \
    || fail "retired Pi cleanup did not explain its escaping-hard-link refusal"
[ -f "$hardlinked_retired_pi_target/owned" ] \
    && [ -f "$hardlinked_retired_pi_home/escaped-hard-link" ] \
    || fail "retired Pi cleanup mutated an escaping hard-link fixture"

# A delete hook rewrites a file through the already-claimed inode. The second
# content proof must catch it and restore the changed target instead of deleting
# recursively under stale authority.
rewritten_retired_pi_home="$skip_test_dir/rewritten-retired-pi-home"
rewritten_retired_pi_target="$rewritten_retired_pi_home/.local/share/agentstart/resources/pi"
rewritten_retired_pi_hook="$rewritten_retired_pi_home/rewrite-claimed-item"
make_retired_pi_claim_fixture "$rewritten_retired_pi_home"
cat >"$rewritten_retired_pi_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
item=$1
printf 'rewritten through the same inode\n' >"$item/owned"
EOF
chmod +x "$rewritten_retired_pi_hook"
set +e
rewritten_retired_pi_output=$(AGENTSTART_PI_CLEANUP_HOME="$rewritten_retired_pi_home" \
    AGENTSTART_TEST_PI_DELETE_HOOK="$rewritten_retired_pi_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
rewritten_retired_pi_status=$?
set -e
[ "$rewritten_retired_pi_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a same-inode rewrite before deletion"
printf '%s\n' "$rewritten_retired_pi_output" \
    | grep -F 'rewritten before deletion' >/dev/null \
    || fail "retired Pi cleanup did not explain its same-inode rewrite refusal"
grep -F 'rewritten through the same inode' "$rewritten_retired_pi_target/owned" >/dev/null \
    || fail "retired Pi cleanup deleted or failed to restore a rewritten claim"
[ ! -e "$rewritten_retired_pi_home/.local/state/agentstart/retirement-quarantine" ] \
    || fail "retired Pi cleanup left its quarantine after restoring a rewritten claim"

# Recreating a public target after claim-all blocks irreversible mutation. The
# foreign occupant stays public and the original claim stays quarantined for a
# human to resolve; neither one becomes deletion authority for the other.
recreated_retired_pi_home="$skip_test_dir/recreated-retired-pi-home"
recreated_retired_pi_target="$recreated_retired_pi_home/.local/share/agentstart/resources/pi"
recreated_retired_pi_hook="$recreated_retired_pi_home/recreate-public-target"
make_retired_pi_claim_fixture "$recreated_retired_pi_home"
cat >"$recreated_retired_pi_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
fixture_home=$2
target="$fixture_home/.local/share/agentstart/resources/pi"
mkdir "$target"
printf 'foreign recreation\n' >"$target/foreign"
EOF
chmod +x "$recreated_retired_pi_hook"
set +e
recreated_retired_pi_output=$(AGENTSTART_PI_CLEANUP_HOME="$recreated_retired_pi_home" \
    AGENTSTART_TEST_PI_AFTER_CLAIMS_HOOK="$recreated_retired_pi_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
recreated_retired_pi_status=$?
set -e
[ "$recreated_retired_pi_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a public-path recreation after claim-all"
printf '%s\n' "$recreated_retired_pi_output" \
    | grep -F 'reappeared after the claim-all barrier' >/dev/null \
    || fail "retired Pi cleanup did not explain its public-path recreation refusal"
[ -f "$recreated_retired_pi_target/foreign" ] \
    && [ -d "$recreated_retired_pi_home/.local/state/agentstart/retirement-quarantine" ] \
    || fail "retired Pi cleanup discarded a public recreation or its preserved original claim"

# The final audit remains authoritative after deletion. A recreated retired
# path makes the run fail without deleting the new occupant.
final_recreated_retired_pi_home="$skip_test_dir/final-recreated-retired-pi-home"
final_recreated_retired_pi_target="$final_recreated_retired_pi_home/.local/share/agentstart/resources/pi"
final_recreated_retired_pi_hook="$final_recreated_retired_pi_home/recreate-final-target"
make_retired_pi_claim_fixture "$final_recreated_retired_pi_home"
cat >"$final_recreated_retired_pi_hook" <<'EOF'
#!/bin/bash
set -euo pipefail
fixture_home=$1
target="$fixture_home/.local/share/agentstart/resources/pi"
mkdir -p "$target"
printf 'post-delete recreation\n' >"$target/foreign"
EOF
chmod +x "$final_recreated_retired_pi_hook"
set +e
final_recreated_retired_pi_output=$(AGENTSTART_PI_CLEANUP_HOME="$final_recreated_retired_pi_home" \
    AGENTSTART_TEST_PI_FINAL_HOOK="$final_recreated_retired_pi_hook" \
    "$root/scripts/remove-retired-pi" --install 2>&1)
final_recreated_retired_pi_status=$?
set -e
[ "$final_recreated_retired_pi_status" -ne 0 ] \
    || fail "retired Pi cleanup accepted a retired path recreated before its final audit"
printf '%s\n' "$final_recreated_retired_pi_output" \
    | grep -F 'retired Pi path remains after cleanup' >/dev/null \
    || fail "retired Pi cleanup did not explain its final recreation refusal"
grep -F 'post-delete recreation' "$final_recreated_retired_pi_target/foreign" >/dev/null \
    || fail "retired Pi cleanup deleted a path recreated for the final audit"

# shellcheck disable=SC2016 # Match the literal embedded Perl durability call.
grep -F '$handle->sync() or die "fsync $path' scripts/remove-retired-pi >/dev/null \
    || fail "retired Pi shared-state redaction is not made durable before success"

# The agent* skill scan finds participants by convention instead of by list:
# an agent* checkout that exports skills/<name>/SKILL.md is a participant, and
# everything else under the root is not. The scan must batch one invocation
# per project naming every skill it found, and no participant is exempt.
code_skills_root="$skip_test_dir/code-root"
code_skills_home="$skip_test_dir/code-home"
code_skills_log="$skip_test_dir/npx.log"
mkdir -p \
    "$code_skills_home" \
    "$code_skills_root/agentbus/skills/bus" \
    "$code_skills_root/agentdemo/skills/demo" \
    "$code_skills_root/agentdemo/skills/second" \
    "$code_skills_root/agentexample/skills/example" \
    "$code_skills_root/agentquiet/src" \
    "$code_skills_root/agentretired/skills/orchestration" \
    "$code_skills_root/notagent/skills/x"
for code_skills_fixture in \
    agentbus/skills/bus \
    agentdemo/skills/demo \
    agentdemo/skills/second \
    agentexample/skills/example \
    agentretired/skills/orchestration \
    notagent/skills/x; do
    code_skills_name=${code_skills_fixture##*/}
    printf -- '---\nname: %s\ndescription: fixture skill\n---\n' "$code_skills_name" \
        >"$code_skills_root/$code_skills_fixture/SKILL.md"
done
# A vendor skill may enumerate provider origins that the fleet has retired.
# The fixed-resource renderer preserves the variable contract but narrows its
# documented values before copying resources into either managed plugin.
cat >>"$code_skills_root/agentdemo/skills/demo/SKILL.md" <<'EOF'

| Variable | Description |
| --- | --- |
| `PLANNOTATOR_ORIGIN` | retired-origin fixture |
EOF
# The portable frontmatter is the invocation-policy source of truth. This
# skill deliberately has no OpenAI manifest; the renderer must create one.
sed -i '' '/^description:/a\
disable-model-invocation: true
' "$code_skills_root/agentdemo/skills/second/SKILL.md"
# OpenAI manifests are portable source: their default prompt starts with the
# plain skill name. Compatibility packaging must qualify only its generated
# copy without changing the canonical fixed resources.
mkdir -p "$code_skills_root/agentdemo/skills/demo/agents"
cat >"$code_skills_root/agentdemo/skills/demo/agents/openai.yaml" <<'EOF'
interface:
  display_name: "Demo"
  short_description: "Exercise compatibility plugin prompt qualification"
  default_prompt: "Use $demo with this fixture."
policy:
  allow_implicit_invocation: false
EOF
# agentdemo carries a post-sync hook (the agentguidance pattern): it must
# appear in the plan, fire after the real sync, and fail the run when it
# fails.
mkdir -p "$code_skills_root/agentdemo/scripts"
cat >"$code_skills_root/agentdemo/scripts/post-sync" <<'EOF'
#!/bin/bash
set -euo pipefail
[ -z "${AGENTSTART_TEST_HOOK_EXIT:-}" ] || exit "$AGENTSTART_TEST_HOOK_EXIT"
marker="$(cd -P -- "$(dirname -- "$0")/.." && pwd)/post-sync-ran"
if [ ! -e "$marker" ]; then
    chmod 444 "$AGENTGUIDANCE_SKILLS_ROOT/demo/agents/openai.yaml"
fi
touch "$marker"
EOF
chmod +x "$code_skills_root/agentdemo/scripts/post-sync"

sync_plan=$(
    HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
        "$root/scripts/sync-skills" --check
)
[ ! -s "$code_skills_log" ] \
    || fail "skill sync plan invoked the skills tool instead of only printing"
printf '%s\n' "$sync_plan" \
    | grep -F "npx --yes skills add \"$code_skills_root/agentdemo\" --agent claude-code --skill demo second --global --copy --yes" \
        >/dev/null \
    || fail "skill sync plan omits the skills discovered in a participating checkout"
printf '%s\n' "$sync_plan" \
    | grep -F "npx --yes skills add \"$code_skills_root/agentexample\" --agent claude-code --skill example --global --copy --yes" \
        >/dev/null \
    || fail "skill sync plan omits a second neutral participant"
if printf '%s\n' "$sync_plan" | grep -Eq 'agentquiet|notagent'; then
    fail "skill sync plan includes a checkout that is not a participant"
fi
printf '%s\n' "$sync_plan" \
    | grep -F "npx --yes skills add \"$code_skills_root/agentbus\" --agent claude-code --skill bus --global --copy --yes" \
        >/dev/null \
    || fail "skill sync plan skips the bus skill, back in service since 2026-08-17"
# A checkout whose every skill is retired drops out of the plan entirely, which
# is what keeps a full install's explicit removal from being undone six hours
# later by the unattended additive path.
if printf '%s\n' "$sync_plan" | grep -Eq 'agentretired|orchestration'; then
    fail "skill sync plan re-adds a retired skill"
fi
printf '%s\n' "$sync_plan" \
    | grep -F "\"$code_skills_root/agentdemo/scripts/post-sync\"" >/dev/null \
    || fail "skill sync plan omits a participant's post-sync hook"
[ ! -e "$code_skills_root/agentdemo/post-sync-ran" ] \
    || fail "skill sync plan ran a post-sync hook instead of only printing"

mkdir -p "$code_skills_home/.codex"
cat >"$code_skills_home/.codex/config.toml" <<'EOF'
model = "fixture-model"

[[skills.config]]
name = "unrelated"
enabled = true

# BEGIN AgentStart managed fleet skills (do not edit)
[[skills.config]]
name = "agent:retired"
enabled = false

# END AgentStart managed fleet skills
EOF

sync_output=$(
    HOME="$code_skills_home" CODEX_HOME="$code_skills_home/.codex" \
        AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
        AGENTSTART_TEST_NPX_OUTPUT=skills-cli-success-noise \
        AGENTSTART_CLAUDE_BIN=/usr/bin/true \
        AGENTSTART_CODEX_BIN=/usr/bin/true \
        "$root/scripts/sync-skills"
)
if printf '%s\n' "$sync_output" | grep -F skills-cli-success-noise >/dev/null; then
    fail "successful skill sync leaked the skills CLI's animated output"
fi
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentdemo> <--agent> <claude-code> <--skill> <demo> <second> <--global> <--copy> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync did not ship both discovered skills in one invocation"
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentexample> <--agent> <claude-code> <--skill> <example> <--global> <--copy> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync skipped a neutral participant"
if grep -E 'agentquiet|notagent' "$code_skills_log" >/dev/null; then
    fail "skill sync synchronized a checkout that is not a participant"
fi
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentbus> <--agent> <claude-code> <--skill> <bus> <--global> <--copy> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync skipped the bus skill, back in service since 2026-08-17"
if grep -E 'agentretired|orchestration' "$code_skills_log" >/dev/null; then
    fail "skill sync re-added a retired skill"
fi
# One invocation each for agentbus, agentdemo, and agentexample.
[ "$(grep -c 'skills> <add>' "$code_skills_log")" -eq 3 ] \
    || fail "skill sync did not invoke the skills tool exactly once per source"
[ -e "$code_skills_root/agentdemo/post-sync-ran" ] \
    || fail "skill sync did not run a participant's post-sync hook after its skills landed"
fixture_resources_root="$code_skills_home/.local/share/agentstart/resources"
fixture_claude_root="$fixture_resources_root/claude/agent"
fixture_codex_root="$fixture_resources_root/codex-marketplace/plugins/agent"
[ -f "$fixture_resources_root/skills/demo/SKILL.md" ] \
    || fail "skill sync did not copy a participant into the fixed resources"
if grep -F 'retired-origin fixture' "$fixture_resources_root/skills/demo/SKILL.md" >/dev/null; then
    fail "fixed-resource rendering retained retired vendor-origin guidance"
fi
# shellcheck disable=SC2016 # Match the literal documented variable.
[ "$(grep -Fc '| `PLANNOTATOR_ORIGIN` |' \
    "$fixture_resources_root/skills/demo/SKILL.md")" -eq 1 ] \
    || fail "fixed-resource rendering did not preserve exactly one PLANNOTATOR_ORIGIN row"
# shellcheck disable=SC2016 # Match the literal documented harness values.
grep -F 'retained fleet harnesses (`claude-code`, `codex`)' \
    "$fixture_resources_root/skills/demo/SKILL.md" >/dev/null \
    || fail "fixed-resource rendering did not narrow PLANNOTATOR_ORIGIN to Claude/Codex"
[ -f "$fixture_claude_root/.claude-plugin/plugin.json" ] \
    || fail "skill sync did not render the Claude fleet plugin"
[ -f "$fixture_resources_root/mcp-servers.json" ] \
    || fail "skill sync did not render the canonical managed MCP resource"
cmp -s config/resources/mcp-servers.json "$fixture_resources_root/mcp-servers.json" \
    || fail "canonical managed MCP resources drifted during rendering"
cmp -s "$fixture_resources_root/mcp-servers.json" "$fixture_claude_root/.mcp.json" \
    || fail "Claude's session-only MCP resource drifted from the canonical copy"
[ -f "$fixture_codex_root/.codex-plugin/plugin.json" ] \
    || fail "skill sync did not render the Codex fleet plugin"
# shellcheck disable=SC2016 # Match the literal Codex plugin-qualified skill reference.
grep -F 'default_prompt: "Use $agent:demo with this fixture."' \
    "$fixture_codex_root/skills/demo/agents/openai.yaml" >/dev/null \
    || fail "the Codex plugin did not qualify demo's default prompt"
# shellcheck disable=SC2016 # Match the literal portable source skill reference.
grep -F 'default_prompt: "Use $demo with this fixture."' \
    "$fixture_resources_root/skills/demo/agents/openai.yaml" >/dev/null \
    || fail "Codex prompt qualification changed the canonical resource manifest"
grep -F 'allow_implicit_invocation: true' \
    "$fixture_resources_root/skills/demo/agents/openai.yaml" >/dev/null \
    || fail "the renderer did not replace stale Codex policy from canonical frontmatter"
[ ! -w "$fixture_resources_root/skills/demo/agents/openai.yaml" ] \
    || fail "the invocation-policy renderer changed a read-only manifest's mode"
grep -F 'allow_implicit_invocation: false' \
    "$fixture_resources_root/skills/second/agents/openai.yaml" >/dev/null \
    || fail "the managed Codex resources did not restrict an explicit-only skill"
grep -F 'allow_implicit_invocation: false' \
    "$fixture_codex_root/skills/second/agents/openai.yaml" >/dev/null \
    || fail "the Codex plugin copy did not restrict an explicit-only skill"
grep -F 'disable-model-invocation: true' \
    "$fixture_resources_root/skills/second/SKILL.md" >/dev/null \
    || fail "the private resources lost explicit-only skill frontmatter"
grep -F 'disable-model-invocation: true' \
    "$fixture_claude_root/skills/second/SKILL.md" >/dev/null \
    || fail "the Claude plugin lost explicit-only skill frontmatter"
"$root/scripts/render-skill-invocation-policy" --check \
    "$fixture_resources_root/skills" >/dev/null \
    || fail "the rendered resources do not pass their invocation-policy audit"
# The audit is independently useful: prove it rejects drift instead of merely
# agreeing with the renderer that just ran.
sed -i '' 's/allow_implicit_invocation: true/allow_implicit_invocation: false/' \
    "$fixture_resources_root/skills/demo/agents/openai.yaml"
if "$root/scripts/render-skill-invocation-policy" --check \
    "$fixture_resources_root/skills" >/dev/null 2>&1; then
    fail "the invocation-policy audit accepted drift from canonical frontmatter"
fi
"$root/scripts/render-skill-invocation-policy" --install \
    "$fixture_resources_root/skills" >/dev/null
chmod 644 "$fixture_resources_root/skills/demo/agents/openai.yaml"
[ ! -e "$fixture_resources_root/pi" ] \
    || fail "skill sync recreated resources for the retired Pi harness"

# The plugin is installed globally, so every managed name must be disabled in
# persistent Codex config before a managed session selectively enables it.
fixture_codex_config="$code_skills_home/.codex/config.toml"
grep -F 'model = "fixture-model"' "$fixture_codex_config" >/dev/null \
    || fail "Codex skill policy replaced unrelated configuration"
grep -F 'name = "unrelated"' "$fixture_codex_config" >/dev/null \
    || fail "Codex skill policy replaced an unrelated skill entry"
for fixture_skill in bus demo second example; do
    grep -F "name = \"agent:$fixture_skill\"" "$fixture_codex_config" >/dev/null \
        || fail "Codex skill policy omitted the managed $fixture_skill skill"
done
[ "$(grep -c '^enabled = false$' "$fixture_codex_config")" -eq 4 ] \
    || fail "Codex skill policy did not disable exactly the managed fixture skills"

# A plugin refresh can fail after persistent policy is written. Keep a retired
# name disabled until a later successful refresh proves the old plugin content
# is gone; pruning it first would make that stale installed skill ambient.
fixture_codex_config_next="$fixture_codex_config.next"
/usr/bin/awk '
    $0 == "# END AgentStart managed fleet skills" {
        print "[[skills.config]]"
        print "name = \"agent:retired\""
        print "enabled = false"
        print ""
    }
    { print }
' "$fixture_codex_config" >"$fixture_codex_config_next"
mv "$fixture_codex_config_next" "$fixture_codex_config"
if HOME="$code_skills_home" CODEX_HOME="$code_skills_home/.codex" \
    AGENTSTART_RESOURCES_ROOT="$fixture_resources_root" \
    AGENTSTART_CODEX_BIN=/usr/bin/false \
    "$root/scripts/render-capabilities" --install >/dev/null 2>&1; then
    fail "Codex resource rendering accepted a failed plugin refresh"
fi
grep -F 'name = "agent:retired"' "$fixture_codex_config" >/dev/null \
    || fail "failed Codex plugin refresh pruned a stale skill disable"
HOME="$code_skills_home" CODEX_HOME="$code_skills_home/.codex" \
    AGENTSTART_RESOURCES_ROOT="$fixture_resources_root" \
    AGENTSTART_CODEX_BIN=/usr/bin/true \
    "$root/scripts/render-capabilities" --install >/dev/null
if grep -F 'name = "agent:retired"' "$fixture_codex_config" >/dev/null; then
    fail "successful Codex plugin refresh did not prune a retired skill disable"
fi
[ "$(grep -c '^enabled = false$' "$fixture_codex_config")" -eq 4 ] \
    || fail "successful Codex plugin refresh changed the managed disable set"

fixture_policy_before=$(/usr/bin/shasum -a 256 "$fixture_codex_config" | awk '{print $1}')
HOME="$code_skills_home" CODEX_HOME="$code_skills_home/.codex" \
    "$root/scripts/sync-codex-skill-policy" \
    "$fixture_resources_root/managed-skills.txt"
fixture_policy_after=$(/usr/bin/shasum -a 256 "$fixture_codex_config" | awk '{print $1}')
[ "$fixture_policy_before" = "$fixture_policy_after" ] \
    || fail "Codex skill policy is not idempotent"

fixture_bad_codex_home="$code_skills_home/bad-codex-home"
mkdir -p "$fixture_bad_codex_home"
printf '%s\n' '# BEGIN AgentStart managed fleet skills (do not edit)' \
    >"$fixture_bad_codex_home/config.toml"
if CODEX_HOME="$fixture_bad_codex_home" "$root/scripts/sync-codex-skill-policy" \
    "$fixture_resources_root/managed-skills.txt" >/dev/null 2>&1; then
    fail "Codex skill policy accepted malformed ownership markers"
fi
[ ! -e "$code_skills_home/.agents/skills/demo" ] \
    || fail "skill sync leaked a managed skill into Fx's compatibility root"

# A failing hook is a failing sync, and the message names the project.
set +e
hook_failure=$(
    HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_HOOK_EXIT=9 \
        "$root/scripts/sync-skills" 2>&1
)
hook_failure_status=$?
set -e
[ "$hook_failure_status" -ne 0 ] \
    || fail "skill sync ignored a failing post-sync hook"
printf '%s\n' "$hook_failure" | grep -F 'agentdemo post-sync hook failed' >/dev/null \
    || fail "post-sync hook failure does not name the project to fix"

# A checkout without skills is silently not a participant, but a participant
# whose synchronization fails is a real error, and the message has to name the
# project: the operator is being asked to go fix that repository.
set +e
scan_failure=$(
    HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" \
        AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
        AGENTSTART_TEST_NPX_OUTPUT=skills-cli-failure-detail \
        AGENTSTART_TEST_NPX_LOCAL_EXIT=9 \
        "$root/scripts/sync-skills" 2>&1
)
scan_failure_status=$?
set -e
[ "$scan_failure_status" -ne 0 ] \
    || fail "skill sync ignored a failing skills tool"
# The scan walks the root in order, so agentbus is the participant that fails.
printf '%s\n' "$scan_failure" | grep -F 'agentbus' >/dev/null \
    || fail "skill sync failure does not name the project to fix"
printf '%s\n' "$scan_failure" | grep -F 'skills-cli-failure-detail' >/dev/null \
    || fail "skill sync hid the skills CLI's captured failure output"

# shellcheck disable=SC2016 # Match the literal internal wrapper invocation.
grep -F '"$script_dir/run-skills-cli" npx --yes skills add' scripts/install.sh >/dev/null \
    || fail "the full installer does not quiet successful external skill installs"
# shellcheck disable=SC2016 # Match the literal internal wrapper invocation.
grep -F '"$script_dir/run-skills-cli" npx --yes skills remove' scripts/install.sh >/dev/null \
    || fail "the full installer does not quiet successful legacy skill removal"

# The installation plan embeds the skill sync's own plan, pointed at the
# fixture tree so the asserted lines are the same on every machine.
install_plan=$(HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" "$root/scripts/install.sh" --check)

# Executor initially lands as a standalone GUI. Grok Build lands as a native
# CLI/TUI without AgentLaunch or Herdr integration.
grep -F 'install_or_upgrade_cask executor' scripts/install.sh >/dev/null \
    || fail "the full installer does not converge the Executor desktop cask"
grep -F 'install_or_upgrade_cask grok-build' scripts/install.sh >/dev/null \
    || fail "the full installer does not converge the Grok Build cask"
if grep -Eq '(codex|claude) mcp add.*executor|add-mcp.*executor|executor mcp' \
    scripts/install.sh; then
    fail "the Executor desktop install also connects it to an agent harness"
fi
if grep -Ei '(codex|claude) mcp add.*(shadcn|livekit)|(shadcn|livekit).*mcp add' \
    scripts/install.sh; then
    fail "the full installer still registers shadcn or LiveKit ambiently"
fi
for removed_mcp in \
    'codex mcp remove shadcn' \
    'codex mcp remove livekit-docs' \
    'claude mcp remove --scope user shadcn' \
    'claude mcp remove --scope user livekit-docs'; do
    grep -F "$removed_mcp" scripts/install.sh >/dev/null \
        || fail "the full installer no longer removes ambient MCP registration: $removed_mcp"
done
# shellcheck disable=SC2016,SC2088 # Plan lines are literal, including $ and ~.
for required_install in \
    '~/code/agentvoice/scripts/install.sh --install  # via install-agent-clis: editable voice TUI + native audio build only; no launch, services or prompt/skill configuration' \
    'brew install or upgrade --cask executor  # standalone GUI only; no MCP or harness registration' \
    'brew install or upgrade --cask grok-build  # official Grok Build CLI/TUI; no AgentLaunch or Herdr integration' \
    'curl -fsSL https://claude.ai/install.sh | XDG_CACHE_HOME=~/Library/Caches bash  # keep vendor staging off a machine-managed ~/.cache symlink' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'curl -fsSL https://plannotator.ai/install.sh | bash -s -- --version v0.27.9 --minimal --non-interactive  # binary only; AgentStart carries the skills' \
    '~/.local/bin/plannotator install-runtime agent-terminal  # managed WebTUI/PTY runtime omitted by the minimal installer' \
    'brew install or upgrade zig  # Native SDK packaging requires it' \
    '~/code/fxnk/scripts/install.sh --install --sha 61eb3da1b8f4286fa52694cf9b032c241ddba224  # exact ship-gate-approved Fx Integration consumer pin' \
    'brew install or upgrade llm  # an AI CLI, so AgentStart'"'"'s outright — moved out of the machine'"'"'s Brewfile' \
    'brew install or upgrade hunk  # review-first diff TUI whose bundled agent skill follows the installed build' \
    'brew install or upgrade rustup  # Terminal Control builds from crates.io with the current stable Rust toolchain' \
    'brew install or upgrade zig@0.15  # Terminal Control'"'"'s libghostty-vt build requires the keg-only 0.15 line' \
    '"$(brew --prefix rustup)/bin/rustup" toolchain install stable --profile minimal' \
    'PATH="$(brew --prefix)/opt/zig@0.15/bin:$PATH" "$(brew --prefix rustup)/bin/rustup" run stable cargo install --locked --root "$HOME/.local" terminal-control' \
    'install AgentStart'"'"'s detached-start shim at ~/.local/bin/termctrl while retaining the upstream executable under ~/.local/libexec/agentstart/terminal-control' \
    'brew install or upgrade herdr only while every default/named server socket is proved inactive  # after cutover, upgrades additionally require explicit inactive-maintenance authorization' \
    'initially select Homebrew Herdr only with explicit inactive-cutover authorization, protocol 20+, and no live or uncertain server sockets, then remove the receipt-proved legacy source build  # ordinary convergence recognizes completed cutover; ambiguous evidence preserves legacy' \
    'herdr integration install claude and codex  # both are pinned to canonical homes, and stale swap-session hooks are pruned' \
    '~/code/smolmux/scripts/install.sh --install  # canonical consumer path: editable smolmux plus its exact source-built smolmux-zmx Companion pin' \
    'scripts/smolmux-config install  # link the Herdr-compatible smolmux key subset with the operator'"'"'s Ctrl-Space prefix' \
    'scripts/herdr-config install  # render, validate, and activate the generated Herdr config, then reload it' \
    'remove AgentStart-owned ~/Library/Application Support/io.datasette.llm/extra-openai-models.yaml symlink  # its extra model records are obsolete' \
    'remove ownership-verified AgentSurface, AgentBus, and Orca harness integrations' \
    'remove the retired Pi CLI package and exact machine state roots, refusing an unproved package or launcher' \
    'remove AgentStart-managed skills from Fx-visible compatibility roots, including retired livekit-simulations  # full install only; independent occupants are preserved' \
    'remove retired skills left in the fixed resources: supervisor supervise orchestrate prompt resource-create resource-update story watch-requests  # full install only; /tend replaces worktree supervision with advisory triage' \
    'npm install --global @native-sdk/cli@0.7  # the line the native-sdk skill documents' \
    'npm install --global agent-browser@0.33.2  # Agentbrowse provider + Agentscrape stable-session driver share this exact build' \
    'ln -sfn "$(realpath "$(npm prefix --global)/bin/agent-browser")" ~/.local/bin/agent-browser  # the candidate Agentscrape resolves before PATH' \
    'scripts/agentbrowse-config install  # link the locked Artbird-first, already-enabled-Apple-second deployment configuration' \
    'scripts/agent-browser-config install  # select agentbrowse'"'"'s short-lived ordered provider; no provider server or static URL' \
    'remove AgentStart'"'"'s retired ~/.local/bin/smolmux-release-local helper  # preserve an independent occupant' \
    'remove ambient shadcn and retired livekit-docs MCP registrations from Codex and Claude Code  # shadcn loads only through AgentLaunch fleet resources' \
    'native skills list' \
    'ln -sfn ~/.local/share/agentstart/resources/guidance/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md' \
    'ln -sfn ~/.local/share/agentstart/resources/guidance/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files' \
    'remove AgentStart-owned ~/AGENTS.md symlink  # retired hub; independent occupants are preserved' \
    'ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES,TOOLS}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against' \
    'install external skill packs with --copy into ~/.local/share/agentstart/resources/skills' \
    'render shadcn as a managed-session MCP server; render no LiveKit MCP or skill' \
    'https://github.com/vercel-labs/skills: find-skills' \
    'https://github.com/anthropics/skills: frontend-design' \
    'https://github.com/vercel-labs/agent-skills: web-design-guidelines, vercel-react-best-practices' \
    'https://github.com/vercel/ai: ai-sdk' \
    'https://github.com/vercel/ai-elements: ai-elements' \
    'https://github.com/shadcn/ui: shadcn' \
    'https://github.com/vercel-labs/native: native-sdk' \
    'https://github.com/backnotprop/plannotator/tree/v0.27.9/apps/skills/core: plannotator, plannotator-review, plannotator-annotate, plannotator-last' \
    'anomalyco/terminal-control@v<installed termctrl version>: terminal-control' \
    'hunk skill path hunk-review  # the review skill ships inside the binary and stays version-matched to it' \
    'install hunk-review with --copy into the fixed resources' \
    'herdr --skill, rendered to ~/.local/share/agentstart/herdr-skill/skills/herdr/SKILL.md  # the surface skill ships inside the binary, so it converges with the installed build, never a stale copy' \
    'install herdr with --copy into the fixed resources' \
    'remove the retired capability-pack tree only with its original manifest or byte-proved fixed-resource residue; refuse every other occupant' \
    'narrow vendor provider-origin guidance to retained Claude/Codex values' \
    'render one session-only Claude plugin named agent (/agent:<skill>)' \
    'render and refresh the skills-only Codex plugin agent@agentstart-managed' \
    'persistently disable every agent:<skill> outside managed Codex sessions' \
    'leave retired-path and ambient-link cleanup to the explicit full installer' \
    "npx --yes skills add \"$code_skills_root/agentdemo\" --agent claude-code --skill demo second --global --copy --yes" \
    "\"$code_skills_root/agentdemo/scripts/post-sync\""; do
    printf '%s\n' "$install_plan" | grep -F "$required_install" >/dev/null \
        || fail "installation plan is missing: $required_install"
done

# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F '"$smolmux_root/scripts/install.sh" --install' scripts/install.sh >/dev/null \
    || fail "the full installer does not delegate to Smolmux's source installer"
if grep -Eq 'SMOLMUX_FX_|smolmux-fx|fx\.json' scripts/install.sh; then
    fail "the installer still assigns Fx or agent-specific ownership to Smolmux"
fi
grep -F 'Preserving independent occupant at retired Smolmux release path' scripts/install.sh >/dev/null \
    || fail "the installer does not preserve an independent retired-path occupant"

# shellcheck disable=SC2016 # Match the literal per-user cache root.
grep -F 'XDG_CACHE_HOME="$HOME/Library/Caches" install_official "Claude Code"' \
    scripts/install.sh >/dev/null \
    || fail "Claude's native installer does not use the stable macOS cache root"

# Plannotator is one versioned unit: the official installer contributes only
# the binary, that binary installs its managed agent-terminal runtime, and the
# same tag's portable core skills enter fleet resources.
grep -F 'plannotator_version=0.27.9' scripts/install.sh >/dev/null \
    || fail "installer does not pin the Plannotator release"
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F '/bin/bash -s -- --version "v$plannotator_version" --minimal --non-interactive' \
    scripts/install.sh >/dev/null \
    || fail "Plannotator installer is not constrained to the pinned binary-only path"
# shellcheck disable=SC2016 # Match the literal verified binary invocation.
grep -F '"$plannotator_bin" install-runtime agent-terminal' scripts/install.sh >/dev/null \
    || fail "installer does not install Plannotator's managed agent-terminal runtime"
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F 'plannotator_skill_source="https://github.com/backnotprop/plannotator/tree/v${plannotator_version}/apps/skills/core"' \
    scripts/install.sh >/dev/null \
    || fail "Plannotator skills are not bound to the installed release's core subtree"
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F 'install_private_skill_pack "$plannotator_skill_source"' scripts/install.sh >/dev/null \
    || fail "installer does not copy the pinned Plannotator skills into fleet resources"
for plannotator_skill in plannotator plannotator-review plannotator-annotate plannotator-last; do
    sed -n '/^remove_legacy_global_skills() {$/,/^}$/p' scripts/install.sh \
        | grep -F "        $plannotator_skill" >/dev/null \
        || fail "ambient cleanup omits AgentStart-managed skill: $plannotator_skill"
done

# Fx remains a required harness, but fxnk owns its fork and installer. This
# repository invokes the public contract and carries no second implementation.
grep -Eq '^fx_integration_sha=[0-9a-f]{40}$' scripts/install.sh \
    || fail "installer does not carry one full lowercase Fx Integration consumer pin"
# shellcheck disable=SC2016 # Match the literal configurable code-root contract.
grep -F 'fxnk_installer="$code_root/fxnk/scripts/install.sh"' scripts/install.sh >/dev/null \
    || fail "installer does not resolve fxnk's Fx installation contract"
# shellcheck disable=SC2016 # Match the literal installer variable invocation.
grep -F '"$fxnk_installer" --install --sha "$fx_integration_sha"' scripts/install.sh >/dev/null \
    || fail "installer does not invoke fxnk's exact-SHA Fx installation contract"
[ ! -e scripts/install-fx ] \
    || fail "AgentStart retains a second Fx installer"
if grep -F 'https://fx.sh/setup.sh' scripts/install.sh >/dev/null; then
    fail "installer retains the official Fx bootstrap beside the integration build"
fi
if grep -F 'upgrade --channel dev' scripts/install.sh >/dev/null; then
    fail "installer retains the Fx dev channel beside the integration build"
fi
# shellcheck disable=SC2016 # Assert the literal environment pin in the installer.
grep -F 'CODEX_HOME="$HOME/.codex" "$herdr_bin" integration install "$harness"' \
    scripts/install.sh >/dev/null \
    || fail "Herdr's Codex integration can inherit a disposable multi-auth CODEX_HOME"
grep -F "codex-multi-auth-runtime-home-[^/']+/herdr-agent-state\\.sh" \
    scripts/install.sh >/dev/null \
    || fail "installer does not prune stale Codex multi-auth Herdr hook definitions"
# shellcheck disable=SC2016 # Assert the literal environment pin in the installer.
grep -F 'CLAUDE_CONFIG_DIR="$HOME/.claude" "$herdr_bin" integration install "$harness"' \
    scripts/install.sh >/dev/null \
    || fail "Herdr's Claude integration can inherit a claude-swap session CLAUDE_CONFIG_DIR"
grep -F "/\\.claude-swap-backup/sessions/" \
    scripts/install.sh >/dev/null \
    || fail "installer does not prune stale Claude swap-session Herdr hook definitions"
printf '%s\n' "$install_plan" | grep -F 'retired livekit-simulations' >/dev/null \
    || fail "installation plan no longer scrubs the retired LiveKit skill"
# A rename or retirement leaves the previous skill directory in the pack, and
# the additive scan never removes it, so stale capabilities would reach every
# session.
grep -F 'remove_retired_pack_skills' scripts/install.sh >/dev/null \
    || fail "installer no longer prunes retired skills left in the fixed resources"
# A second neutral participant proves the plan is convention-driven rather
# than fitted to the first fixture.
printf '%s\n' "$install_plan" \
    | grep -F "skills add \"$code_skills_root/agentexample\"" >/dev/null \
    || fail "installation plan omits a convention-discovered participant"
# The agentchats checkout ships its chats skill through the scan; an explicit
# line would be the second synchronization path its guidance forbids.
if printf '%s\n' "$install_plan" \
    | grep -F '/code/agentchats"' >/dev/null; then
    fail "installation plan still synchronizes chats explicitly beside the scan"
fi
# The agentdesk checkout ships its desktop skill through the same scan; the
# same rule holds.
if printf '%s\n' "$install_plan" \
    | grep -F '/code/agentdesk"' >/dev/null; then
    fail "installation plan still synchronizes desktop explicitly beside the scan"
fi
# The ownership boundary: general-purpose desktop clients and the GitHub CLI
# belong to the machine layer. Executor's standalone integration GUI and Grok
# Build's CLI-only package are the two explicit cask exceptions.
if printf '%s\n' "$install_plan" | grep -F -- '--cask' \
    | grep -Fv \
        -e 'brew install or upgrade --cask executor  # standalone GUI only; no MCP or harness registration' \
        -e 'brew install or upgrade --cask grok-build  # official Grok Build CLI/TUI; no AgentLaunch or Herdr integration' \
    >/dev/null; then
    fail "installation plan contains an unowned Homebrew cask"
fi
if printf '%s\n' "$install_plan" | grep -F 'brew install or upgrade gh' >/dev/null; then
    fail "installation plan crossed the boundary: gh is the machine's"
fi

# shellcheck disable=SC2016 # Match the literal helper invocations in the script.
for sync_invocation in \
    '"$script_dir/sync-skills" --check' \
    '"$script_dir/sync-skills"'; do
    grep -F "$sync_invocation" scripts/install.sh >/dev/null \
        || fail "installer does not run the skill sync: $sync_invocation"
done
# Agentguidance ships through the scan like every participant; an explicit
# line for it here would be the second synchronization path its guidance
# forbids, and the render belongs to its post-sync hook, not to this
# installer.
if grep -En "$operator_account|agentguidance" scripts/install.sh \
    | grep -vF 'prompts/agentguidance' \
    | grep -vF '.config/agentguidance' \
    | grep -vF 'agentguidance renders' \
    | grep -vF "agentguidance's" >/dev/null; then
    fail "installer grew agentguidance handling beyond the extension prompts; the scan and post-sync hook own the rest"
fi
grep -F 'link_agent_guidance' scripts/install.sh >/dev/null \
    || fail "installer does not link the harness guidance"
# shellcheck disable=SC2016 # Match the literal target paths in the script.
grep -F '"$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"' scripts/install.sh >/dev/null \
    || fail "installer does not target both harness guidance locations"
grep -F 'refusing to replace independent guidance' scripts/install.sh >/dev/null \
    || fail "installer would replace independent guidance files"
# shellcheck disable=SC2016 # Match the literal direct-link operation.
grep -F 'ln -sfn "$source" "$target"' scripts/install.sh >/dev/null \
    || fail "installer does not link each harness slot directly to the guidance source"
if grep -F 'home_guidance=' scripts/install.sh >/dev/null \
    || grep -F 'ln -sfn prompts/AGENTS.md ~/AGENTS.md' scripts/install.sh >/dev/null; then
    fail "installer still creates the retired home guidance hub"
fi
grep -q '^ *remove_retired_home_guidance$' scripts/install.sh \
    || fail "installer does not remove its retired home guidance symlink"
grep -F 'link_extension_prompts' scripts/install.sh >/dev/null \
    || fail "installer does not link the operator extension prompts"
grep -F 'refusing to replace independent extension prompt' scripts/install.sh >/dev/null \
    || fail "installer would replace an independent extension prompt"
for prompt_name in SYSTEM.md GUIDELINES.md TOOLS.md; do
    grep -F "$prompt_name" scripts/install.sh >/dev/null \
        || fail "installer does not link the $prompt_name extension prompt"
done
# shellcheck disable=SC2016 # Match the literal home-guidance source path.
grep -F 'source="$repo_root/prompts/AGENTS.md"' scripts/install.sh >/dev/null \
    || fail "installer does not own the harness guidance source"
grep -F 'install_or_upgrade_formula llm' scripts/install.sh >/dev/null \
    || fail "installer does not converge the llm CLI"
grep -F 'remove_retired_llm_config' scripts/install.sh >/dev/null \
    || fail "installer does not retire its obsolete llm model configuration"
# shellcheck disable=SC2016 # Match the literal ownership check in the script.
grep -F 'readlink "$target"' scripts/install.sh >/dev/null \
    || fail "installer does not verify ownership before removing the retired llm configuration"
if grep -F 'link_llm_config' scripts/install.sh >/dev/null; then
    fail "installer still links the obsolete llm model configuration"
fi

# The native-sdk skill documents the 0.7 line and Zig builds Native SDK
# applications, so both stay pinned rather than tracking latest. agent-browser is pinned because
# Agentbrowse's provider protocol and Agentscrape's driver behavior are tested
# against that exact build.
grep -F 'native_sdk_version=0.7' scripts/install.sh >/dev/null \
    || fail "installer does not pin the Native SDK CLI to the compatible 0.7 line"
if grep -F '@native-sdk/cli@latest' scripts/install.sh >/dev/null; then
    fail "installer tracks the latest Native SDK CLI release"
fi
grep -F 'install_or_upgrade_formula zig' scripts/install.sh >/dev/null \
    || fail "installer does not converge the Zig toolchain"

# Terminal Control is built from its locked crates.io release with the exact
# Zig line libghostty-vt requires. Its upstream skill is selected from the
# installed binary's matching release tag and then shipped through the common
# fixed private resources to Claude Code and Codex.
grep -F 'install_or_upgrade_formula rustup' scripts/install.sh >/dev/null \
    || fail "installer does not converge Rustup for Terminal Control"
# shellcheck disable=SC2016 # Match the literal formula-owned Rustup variable.
grep -F '"$rustup_bin" toolchain install stable --profile minimal' scripts/install.sh >/dev/null \
    || fail "installer does not converge a current Rust toolchain for Terminal Control"
# shellcheck disable=SC2016 # Match the literal cargo install root and Zig path.
grep -F 'PATH="$brew_prefix/opt/zig@0.15/bin:$PATH"' scripts/install.sh >/dev/null \
    || fail "Terminal Control is not built with the required Zig 0.15 line"
# shellcheck disable=SC2016 # Match the literal cargo install root.
grep -F 'cargo install --locked --root "$HOME/.local" terminal-control' scripts/install.sh >/dev/null \
    || fail "installer does not converge the locked Terminal Control crate"
grep -F '# AgentStart-managed Terminal Control shim.' \
    config/terminal-control/termctrl >/dev/null \
    || fail "Terminal Control shim is missing its ownership marker"
# shellcheck disable=SC2016 # Match the literal private upstream payload path.
grep -F 'termctrl_real_dir="$HOME/.local/libexec/agentstart/terminal-control"' \
    scripts/install.sh >/dev/null \
    || fail "installer does not retain the upstream Terminal Control executable under libexec"
grep -F "grep -F -m 1 '# AgentStart-managed Terminal Control shim.'" \
    scripts/install.sh >/dev/null \
    || fail "installer cannot recognize and restore its Terminal Control shim before Cargo runs"
# shellcheck disable=SC2016 # Match the literal shim and public binary variables.
grep -F 'install -m 0755 "$termctrl_shim" "$termctrl_bin"' \
    scripts/install.sh >/dev/null \
    || fail "installer does not put the Terminal Control shim at the public command path"
# shellcheck disable=SC2016 # Match the literal version variable in the skill source.
grep -F '"anomalyco/terminal-control@v$terminal_control_version" terminal-control' \
    scripts/install.sh >/dev/null \
    || fail "installer does not bind the Terminal Control skill to the installed CLI release"
# shellcheck disable=SC2016 # Backticks name the advertised skill literally.
grep -F '`terminal-control` — real terminal applications:' \
    prompts/agentguidance/TOOLS.md >/dev/null \
    || fail "TOOLS.md does not advertise the Terminal Control skill"
grep -F 'desktop, terminal-control' skills/fleet/MAP.md >/dev/null \
    || fail "the fleet skill route map omits the Terminal Control advertisement"
# shellcheck disable=SC2016 # Backticks name the advertised skill literally.
grep -F '`attention` — durable human handoff' \
    prompts/agentguidance/TOOLS.md >/dev/null \
    || fail "TOOLS.md does not advertise the Attention skill"
# shellcheck disable=SC2016 # Backticks name the advertised skill literally.
grep -F '`chats` — every past Claude Code and Codex session' \
    prompts/agentguidance/TOOLS.md >/dev/null \
    || fail "TOOLS.md does not advertise the session history skill"
grep -F 'board & groom & chats' skills/fleet/MAP.md >/dev/null \
    || fail "the fleet skill route map omits the chats advertisement"

# Herdr stages the official stable Homebrew formula but must retain the
# compatible source-built client while the formula is below fleet protocol 20
# or any default/named server socket exists. The retired updater is absent,
# and inactive cutover removes its binary only when the 40-hex receipt,
# regular-file shape, owner, and write-time all agree.
grep -F 'install_or_upgrade_formula zig@0.15' scripts/install.sh >/dev/null \
    || fail "installer does not converge the Zig 0.15 line Terminal Control builds against"
grep -F 'install_or_upgrade_formula herdr' scripts/install.sh >/dev/null \
    || fail "installer does not converge the official stable Herdr formula"
# shellcheck disable=SC2016 # Match the literal selector invocation.
grep -F 'herdr_socket_state=$("$script_dir/select-herdr-runtime" --socket-state)' scripts/install.sh >/dev/null \
    || fail "installer does not inspect Herdr sockets before Homebrew convergence"
# shellcheck disable=SC2016 # Match the literal selector invocation.
grep -F 'herdr_legacy_state=$("$script_dir/select-herdr-runtime" --legacy-state)' scripts/install.sh >/dev/null \
    || fail "installer does not distinguish pre-cutover, post-cutover, and clean-install state"
grep -F 'Deferring Homebrew Herdr installation or upgrade while a server socket is present.' scripts/install.sh >/dev/null \
    || fail "installer does not preserve installed Herdr client bytes around a live server"
grep -F 'Deferring post-cutover Homebrew Herdr upgrade without explicit inactive-maintenance authorization.' scripts/install.sh >/dev/null \
    || fail "installer can race a post-cutover formula upgrade against a new server"
[ ! -e scripts/update-herdr ] \
    || fail "retired source updater still exists"
# shellcheck disable=SC2016 # Match the literal checkout path.
if grep -F '$HOME/src/herdr' scripts/install.sh >/dev/null; then
    fail "installer still binds the Herdr source checkout"
fi
# Anchored to an invocation: normal stable updates belong to Homebrew.
if grep -E '^[[:space:]]*herdr update' scripts/install.sh >/dev/null; then
    fail "installer grows a second Herdr update path beside Homebrew"
fi
if grep -F 'herdr.dev/install.sh' scripts/install.sh >/dev/null; then
    fail "installer uses Herdr's direct installer instead of Homebrew"
fi
# shellcheck disable=SC2016 # Match the exact selector invocation.
grep -F 'herdr_bin=$("$script_dir/select-herdr-runtime" "$brew_prefix/bin/herdr")' scripts/install.sh >/dev/null \
    || fail "installer does not select a safe Herdr runtime after staging Homebrew"
grep -F 'fleet_minimum_protocol=20' scripts/select-herdr-runtime >/dev/null \
    || fail "Herdr cutover does not enforce fleet protocol 20"
# shellcheck disable=SC2016 # Match the literal configurable protocol expression.
grep -F '[ "$minimum_protocol" -ge "$fleet_minimum_protocol" ]' scripts/select-herdr-runtime >/dev/null \
    || fail "Herdr cutover allows its protocol floor to be lowered"
# shellcheck disable=SC2016 # Match the literal socket-root variable.
grep -F 'server_socket_state "$herdr_config_root"' scripts/select-herdr-runtime >/dev/null \
    || fail "Herdr cutover does not conservatively inspect default and named server sockets"
# shellcheck disable=SC2016 # Match the literal completed-cutover predicate.
grep -F 'if [ "$legacy_evidence_present" -eq 0 ]; then' scripts/select-herdr-runtime >/dev/null \
    || fail "Herdr runtime selection does not recognize a completed cutover"
# shellcheck disable=SC2016 # Match the literal config-root uncertainty guard.
grep -F '[ ! -L "$herdr_config_root" ]' scripts/select-herdr-runtime >/dev/null \
    || fail "Herdr cutover follows an uncertain socket-root symlink"
grep -F 'AGENTSTART_HERDR_ALLOW_CUTOVER must be 0 or 1' scripts/select-herdr-runtime >/dev/null \
    || fail "Herdr cutover does not require explicit authorization"
# shellcheck disable=SC2016 # Match literal legacy cleanup variables and predicates.
grep -F 'legacy_herdr_receipt="$legacy_herdr_state/herdr-built-commit"' scripts/select-herdr-runtime >/dev/null \
    || fail "installer does not recognize the retired source-build receipt"
# shellcheck disable=SC2016 # Match the literal legacy receipt variable.
grep -F '[[ "$legacy_herdr_commit" =~ ^[0-9a-f]{40}$ ]]' scripts/select-herdr-runtime >/dev/null \
    || fail "legacy Herdr cleanup does not validate the receipt"
# shellcheck disable=SC2016 # Match the literal legacy binary variable.
grep -F '[ ! -L "$legacy_herdr_bin" ]' scripts/select-herdr-runtime >/dev/null \
    || fail "legacy Herdr cleanup could remove an independent symlink"
grep -F "stat -f '%Su' \"\$legacy_herdr_bin\"" scripts/select-herdr-runtime >/dev/null \
    || fail "legacy Herdr cleanup does not prove the binary owner"
grep -F "stat -f '%m' \"\$legacy_herdr_bin\"" scripts/select-herdr-runtime >/dev/null \
    || fail "legacy Herdr cleanup does not match the updater write time"
# shellcheck disable=SC2016 # Match the literal legacy binary variable.
grep -F 'rm -- "$legacy_herdr_bin"' scripts/select-herdr-runtime >/dev/null \
    || fail "installer does not remove its proved legacy Herdr binary"
# shellcheck disable=SC2016 # Match the literal legacy state variables.
grep -F 'rm -f -- "$legacy_herdr_receipt" "$legacy_herdr_build_log"' scripts/select-herdr-runtime >/dev/null \
    || fail "installer does not retire its Herdr build state"
# shellcheck disable=SC2016 # Match the literal Homebrew resolution assertion.
grep -F '[ "$(command -v herdr)" = "$herdr_bin" ]' scripts/install.sh >/dev/null \
    || fail "installer does not verify that Homebrew Herdr wins resolution"
grep -F 'install_herdr_integrations' scripts/install.sh >/dev/null \
    || fail "installer does not converge the herdr harness integrations"
grep -F 'for harness in claude codex' scripts/install.sh >/dev/null \
    || fail "herdr integrations do not cover both harnesses the fleet runs"

# AgentStart owns Herdr's behavior config and renders it into the live file,
# because Herdr writes its own keys there. It carries no palette: Herdr's
# `terminal` theme follows the terminal, which runs its own default colors.
[ -s config/herdr/config.toml ] \
    || fail "AgentStart's Herdr base config is missing"
grep -F 'plugin pane open --plugin agentsurface --entrypoint launch' \
    config/herdr/config.toml >/dev/null \
    || fail "AgentSurface binding does not open its plugin launch pane"
grep -F 'plugin pane open --plugin agentsurface --entrypoint usage' \
    config/herdr/config.toml >/dev/null \
    || fail "agentusage binding does not open its AgentSurface plugin pane"
grep -F 'plugin pane open --plugin agentsurface --entrypoint chats' \
    config/herdr/config.toml >/dev/null \
    || fail "the session history picker binding does not open its AgentSurface plugin pane"
grep -F 'HERDR_ACTIVE_PANE_CWD' config/herdr/config.toml >/dev/null \
    || fail "AgentSurface plugin popup does not preserve the active pane cwd"
for action in pane tab workspace; do
    grep -Fqx "close_${action} = \"\"" config/herdr/config.toml \
        || fail "Herdr's immediate close_${action} action is still enabled"
done
for target in pane tab workspace; do
    grep -F "plugin pane open --plugin agentsurface --entrypoint confirm-close-${target}" \
        config/herdr/config.toml >/dev/null \
        || fail "Herdr ${target} close does not open its AgentSurface confirmation pane"
done
if grep -E 'confirm-close-(pane|tab|workspace).*--target-pane' \
    config/herdr/config.toml >/dev/null; then
    fail "Herdr popup close confirmations pass unsupported layout targets"
fi
grep -F 'command = "agentsurface launch"' config/herdr/config.toml >/dev/null \
    && fail "AgentSurface binding still opens an untitled generic popup"
grep -F 'command = "escape-to-quit agentusage"' config/herdr/config.toml >/dev/null \
    && fail "agentusage binding still opens an untitled generic popup"
if grep -E 'key = "prefix\+[\[\]]"' config/herdr/config.toml >/dev/null; then
    fail "Herdr config still contains theme-cycling bindings"
fi
sidebar_settings=$(grep -E '^sidebar_[[:alnum:]_]* = ' config/herdr/config.toml || true)
[ "$sidebar_settings" = 'sidebar_max_width = 106
sidebar_collapsed_mode = "hidden"' ] \
    || fail "Herdr sidebar does not keep its 50%-of-screen width allowance and hidden collapsed mode"
if grep -E '^status_indicators = ' config/herdr/config.toml >/dev/null; then
    fail "Herdr config still customizes the left sidebar beyond its width, sort, and agent rows"
fi
# Herdr overwrites the runtime agent sort from config on every reload, so an
# absent key does not mean "leave it alone" — it means the in-app toggle
# reverts to grouped whenever this file changes.
grep -F 'agent_panel_sort = "priority"' config/herdr/config.toml >/dev/null \
    || fail "Herdr agent panel does not hold the priority sort across config reloads"
# The Agents panel must name the project (root repository plus worktree branch)
# and the conversation slug AgentSurface publishes. Herdr's defaults draw the
# workspace label and the harness kind instead, which identify neither, and
# this has regressed twice — pin the rows, not just the section.
grep -F '[ui.sidebar.agents]' config/herdr/config.toml >/dev/null \
    || fail "Herdr agent sidebar rows are missing"
grep -F "[\"state_icon\", { token = \"\$project\", bold = true, dim = false }]," \
    config/herdr/config.toml >/dev/null \
    || fail "Herdr agent sidebar does not lead with AgentSurface's \$project token"
grep -F "[\"\$conversation\"]," config/herdr/config.toml >/dev/null \
    || fail "Herdr agent sidebar does not show AgentSurface's \$conversation slug"
grep -F 'delivery = "off"' config/herdr/config.toml >/dev/null \
    || fail "Herdr native notifications are not disabled"
grep -Fqx 'version_check = true' config/herdr/config.toml \
    || fail "Herdr stable version checking is not enabled"
for sound in "done" request; do
    [ -s "assets/herdr-sounds/${sound}.mp3" ] \
        || fail "Herdr ${sound} sound is missing from AgentStart"
    grep -Fqx "${sound}_path = \"../../code/agentstart/assets/herdr-sounds/${sound}.mp3\"" \
        config/herdr/config.toml \
        || fail "Herdr ${sound} sound does not resolve to AgentStart's owned asset"
done
if grep -F 'code/funk/assets/herdr-sounds' config/herdr/config.toml >/dev/null; then
    fail "Herdr sound config still crosses into Funk"
fi
grep -Fqx 'name = "terminal"' config/herdr/config.toml \
    || fail "Herdr does not follow the terminal's own palette"
if grep -Eq '^\[theme\.custom\]' config/herdr/config.toml; then
    fail "Herdr config carries a custom palette instead of following the terminal"
fi
# The theme manager was removed outright: Tinty, its templates, its generated
# palettes, and the Ghostty theme it rendered. This scan covers everything that
# could reintroduce one — config, scripts, prompts, and the two documents that
# describe the shape. It excludes tests/, where these names are the thing being
# banned, and the fleet map, which records the removal in its history.
theme_manager_refs=$(grep -R -Eih 'tinty|tinted-theming|base16|base24|chalk' \
    config scripts prompts README.md CONTEXT.md || true)
# The sole survivor is the marker herdr-config recognizes so a machine still
# carrying the retired render gets migrated rather than refused. It can go once
# every machine has converged past it.
[ "$theme_manager_refs" = 'legacy_marker="# Generated by AgentStart'"'"'s herdr-tinty. Do not edit."' ] \
    || fail "a theme manager reference returned to AgentStart"
[ ! -e config/tinty ] \
    || fail "the retired Tinty configuration is still in the checkout"
[ ! -e scripts/herdr-tinty ] \
    || fail "the retired herdr-tinty helper is still in the checkout"
# Smolmux owns its editable command, exact Companion pin, and doctor verification
# in its canonical source installer. AgentStart supplies only the shared binary
# destination and does not restore Smolmux's retired agent/Fx ownership.
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F 'SMOLMUX_INSTALL_BIN_DIR="$HOME/.local/bin"' scripts/install.sh >/dev/null \
    || fail "installer does not give Smolmux the shared binary destination"
# shellcheck disable=SC2016 # Match literal installer variables.
grep -F '"$smolmux_root/scripts/install.sh" --install' scripts/install.sh >/dev/null \
    || fail "installer does not invoke smolmux's canonical source installer"
if grep -F 'Dcompanion' scripts/install.sh >/dev/null; then
    fail "installer builds the Companion by hand instead of through smolmux's script"
fi
# smolmux's config is linked because smolmux does not mutate it; both the tracked source
# and the installer stay pinned to the same Ctrl-Space prefix used by Herdr.
grep -Fqx 'prefix = "ctrl+space"' config/smolmux/config.toml \
    || fail "smolmux config does not use the operator's Ctrl-Space prefix"
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F '"$script_dir/smolmux-config" install' scripts/install.sh >/dev/null \
    || fail "installer does not link the smolmux config"
tests/smolmux-config.sh
tests/agentmux-config.sh

# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F 'AGENTSTART_HERDR_BIN="$herdr_bin" "$script_dir/herdr-config" install' scripts/install.sh >/dev/null \
    || fail "installer does not render the Herdr config"
tests/herdr-homebrew-cutover.sh
tests/herdr-config.sh

# The AgentSurface popup-pane and tab-naming plugin registers by checkout path;
# linking every run is the converge, and a missing agentsurface checkout is a
# skip, not a failure.
grep -F 'install_herdr_plugins' scripts/install.sh >/dev/null \
    || fail "installer does not link the agentsurface herdr plugin"
# shellcheck disable=SC2016 # Match the literal link invocation, $-sign and all.
grep -F '"$herdr_bin" plugin link "$plugin_root"' scripts/install.sh >/dev/null \
    || fail "the agentsurface plugin is not registered by checkout path"
grep -F 'protocol_mismatch' scripts/install.sh >/dev/null \
    || fail "plugin convergence cannot preserve a newer resident server"
grep -F 'relink deferred until the natural Herdr server restart' scripts/install.sh >/dev/null \
    || fail "deferred plugin convergence does not report the client/server skew"
# The surface skill ships inside the binary (`herdr --skill`) and converges
# with the installed build; a GitHub-sourced copy would track a different
# head than the installed herdr and grow a second update path.
grep -F 'install_herdr_skill' scripts/install.sh >/dev/null \
    || fail "installer does not converge the herdr surface skill"
# shellcheck disable=SC2016 # Match the literal selected runtime variable.
grep -F '"$herdr_bin" --skill' scripts/install.sh >/dev/null \
    || fail "the herdr skill is not rendered from the installed binary"
if grep -E 'skills add https://github.com/[^ ]*herdr' scripts/install.sh >/dev/null; then
    fail "the herdr skill tracks the GitHub head instead of the installed binary"
fi
# Hunk's bundled skill is generated from the same command surface as the
# installed binary. A GitHub-sourced copy could move ahead of Homebrew and
# teach agents flags their local Hunk does not accept.
grep -F 'install_or_upgrade_formula hunk' scripts/install.sh >/dev/null \
    || fail "installer does not install Hunk through its Homebrew update path"
grep -F 'install_hunk_skill' scripts/install.sh >/dev/null \
    || fail "installer does not converge the bundled Hunk review skill"
grep -F 'hunk skill path hunk-review' scripts/install.sh >/dev/null \
    || fail "installer does not resolve the review skill from the installed Hunk binary"
# shellcheck disable=SC2016 # Match the literal pack-root variable in the installer.
grep -F 'install_private_skill_pack "$pack_root" hunk-review' scripts/install.sh >/dev/null \
    || fail "installer does not copy Hunk's bundled review skill into the fixed resources"
if grep -E 'skills add https://github.com/[^ ]*modem-dev/hunk' scripts/install.sh >/dev/null; then
    fail "the Hunk review skill tracks GitHub head instead of the installed binary"
fi
grep -F 'agent_browser_version=0.33.2' scripts/install.sh >/dev/null \
    || fail "installer does not pin the Agentbrowse- and Agentscrape-bound agent-browser build"
grep -F 'refusing to replace independent file' scripts/agent-browser-link.sh >/dev/null \
    || fail "installer would replace an independent ~/.local/bin/agent-browser"
# shellcheck disable=SC2016 # Match the literal command substitution in the installer.
grep -F 'agent_browser_npm_prefix=$(npm prefix --global)' scripts/install.sh >/dev/null \
    || fail "installer does not resolve agent-browser from npm's global prefix"
# shellcheck disable=SC2016 # Match the literal variable reference in the installer.
grep -F 'link_agent_browser "$agent_browser_npm_prefix"' scripts/install.sh >/dev/null \
    || fail "installer does not publish npm's physical agent-browser entrypoint"

# The fleet statusline is one bar in two harness idioms: a render command for
# Claude and an ordered pick from Codex's fixed item set. Codex has no custom
# renderer to install.
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-statusline" --install' scripts/install.sh >/dev/null \
    || fail "installer does not converge the fleet statusline"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-statusline" --check' scripts/install.sh >/dev/null \
    || fail "installation plan omits the fleet statusline"
[ -x scripts/install-statusline ] \
    || fail "the statusline installer is not executable"
[ -s config/statusline/claude-statusline.sh ] \
    || fail "Claude statusline renderer is missing or empty"
# Claude refuses an independent statusline.
grep -F 'refusing to replace an independent claude renderer' scripts/install-statusline >/dev/null \
    || fail "the statusline installer would replace an independent Claude file"
if grep -F 'agent-hooks/claude-statusline.sh' config/statusline/claude-statusline.sh >/dev/null; then
    fail "the claude renderer still forwards statusline payloads to the retired Orca sink"
fi
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-agent-clis"' scripts/install.sh >/dev/null \
    || fail "installer does not install the agent CLIs"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$agent_clis_status"' scripts/install.sh >/dev/null \
    || fail "installer does not propagate an agent CLI installation failure"
# The provider default must land only after the checkout-owned installer has
# succeeded, so a full converge cannot select a command it failed to install.
# shellcheck disable=SC2016 # Match the literal helper invocations in install.sh.
agent_clis_line=$(grep -n '^"$script_dir/install-agent-clis"' scripts/install.sh | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal helper invocations in install.sh.
agentbrowse_config_line=$(grep -n '^"$script_dir/agentbrowse-config" install$' scripts/install.sh | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal helper invocations in install.sh.
agent_browser_config_line=$(grep -n '^"$script_dir/agent-browser-config" install$' scripts/install.sh | cut -d: -f1)
[ -n "$agent_clis_line" ] && [ -n "$agentbrowse_config_line" ] && [ -n "$agent_browser_config_line" ] \
    && [ "$agentbrowse_config_line" -gt "$agent_clis_line" ] \
    && [ "$agent_browser_config_line" -gt "$agentbrowse_config_line" ] \
    || fail "agentbrowse and agent-browser configs must be linked in order after the CLIs install"

# Agentweb retirement has a load-bearing activation order: the migrated
# Agentscrape command deploys in the CLI phase; service convergence then boots
# out and removes the owned broker while rewriting Agentbrain; only after that
# call returns may the command wrappers and receipt disappear.
# shellcheck disable=SC2016 # Match the literal helper invocation in install.sh.
launchagents_line=$(grep -n '^"$script_dir/install-launchagents" --install$' scripts/install.sh | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal helper invocation in install.sh.
retired_agentweb_line=$(grep -n '^"$script_dir/remove-retired-agentweb" --install$' scripts/install.sh | cut -d: -f1)
[ -n "$launchagents_line" ] && [ -n "$retired_agentweb_line" ] \
    && [ "$launchagents_line" -gt "$agent_clis_line" ] \
    && [ "$retired_agentweb_line" -gt "$launchagents_line" ] \
    || fail "Agentweb retirement does not preserve CLI, service, then command-cleanup order"
# shellcheck disable=SC2016 # Match the literal helper invocation in check mode.
launchagents_check_line=$(grep -n '^    "$script_dir/install-launchagents" --check$' scripts/install.sh | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal helper invocation in check mode.
retired_agentweb_check_line=$(grep -n '^    "$script_dir/remove-retired-agentweb" --check$' scripts/install.sh | cut -d: -f1)
[ -n "$launchagents_check_line" ] && [ -n "$retired_agentweb_check_line" ] \
    && [ "$retired_agentweb_check_line" -gt "$launchagents_check_line" ] \
    || fail "check mode does not report Agentweb service retirement before command cleanup"
if grep -F 'remove-retired-agentweb' scripts/remove-retired-integrations >/dev/null; then
    fail "Agentweb command cleanup runs in the early retired-integrations phase"
fi
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/remove-retired-integrations"' scripts/install.sh >/dev/null \
    || fail "installer does not run retired integration cleanup"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$retired_integrations_status"' scripts/install.sh >/dev/null \
    || fail "installer does not propagate retired integration cleanup failures"
grep -F 'skills remove --global --yes' scripts/install.sh >/dev/null \
    || fail "full installer does not remove retired global skills"
if grep -F 'skills remove' scripts/sync-skills >/dev/null; then
    fail "sync-skills removes skills on the unattended path"
fi
grep -F 'remove_retired_core_plugin' scripts/install.sh >/dev/null \
    || fail "full installer does not retire the old core plugin"
if grep -Eq 'plugin (uninstall|remove)|plugin marketplace remove' scripts/render-capabilities; then
    fail "render-capabilities uninstalls plugins on the unattended path"
fi
# shellcheck disable=SC2016 # Match literal generated-manifest variables.
grep -F 'mv -f -- "$manifest.next" "$manifest"' scripts/render-capabilities >/dev/null \
    || fail "render-capabilities may prompt before replacing an immutable generated manifest"
# shellcheck disable=SC2016 # Match the literal helper invocation.
grep -F '"$script_dir/remove-retired-pi" --install' scripts/install.sh >/dev/null \
    || fail "full installer does not run the exact-target Pi retirement cleanup"
# The list spans two lines, so the order is checked on the joined text rather
# than by matching one literal line. agentusage must precede agentlaunch (the
# launcher shells its balance contract), and codex-swap plus grok-swap must
# precede agentusage so balance observes the command owners they install.
agent_cli_order=$(tr '\n' ' ' <scripts/install-agent-clis | tr -s ' ')
case "$agent_cli_order" in
    *"for tool in agentwiki agentboard agentbrowse-infra agentbrowse agentattention agentutils agentsearch agentkeys agentsource agentscrape \\ agentbrain codex-swap grok-swap agentusage agentlaunch agentsurface"*) ;;
    *) fail "agent CLI installer changed its tool list or ordering" ;;
esac
# Every checkout with an installer is in the loop; a name missing from it is a
# tool nothing installs.
for expected_tool in agentwiki agentboard agentbrowse-infra agentbrowse agentattention agentutils agentsearch agentkeys agentsource \
    agentscrape agentbrain codex-swap grok-swap agentusage agentlaunch agentsurface agentgrok agentvoice; do
    case "$agent_cli_order" in
        *" $expected_tool "*) ;;
        *) fail "agent CLI loop no longer installs $expected_tool" ;;
    esac
done
case "$agent_cli_order" in
    *" agentbus "*) fail "agent CLI loop still installs retired agentbus" ;;
    *" agentweb "*) fail "agent CLI loop still installs retired agentweb" ;;
esac
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentchats_root="$code_root/agentchats"' scripts/install.sh >/dev/null \
    || fail "installer does not own the agentchats installation call"
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentdesk_root="$code_root/agentdesk"' scripts/install.sh >/dev/null \
    || fail "installer does not own the peekaboo installation call"
# One fleet root, honoured by every script that walks it. A script resolving
# $HOME/code directly cannot be pointed at a fixture tree, and one resolving it
# relative to its own location would silently skip the whole fleet on a worktree
# run — the checkouts are found where the machine keeps them, not beside $0.
for fleet_walker in scripts/install.sh scripts/install-agent-clis \
    scripts/remove-retired-integrations scripts/sync-skills; do
    # shellcheck disable=SC2016 # Match the literal knob in each script.
    grep -F 'code_root="${AGENTSTART_CODE_ROOT:-$HOME/code}"' "$fleet_walker" >/dev/null \
        || fail "$fleet_walker does not resolve the fleet root through AGENTSTART_CODE_ROOT"
    # shellcheck disable=SC2016 # A bare $HOME/code path bypasses the knob.
    if grep -n '\$HOME/code' "$fleet_walker" | grep -vF 'AGENTSTART_CODE_ROOT' >/dev/null; then
        fail "$fleet_walker still resolves \$HOME/code directly instead of through code_root"
    fi
done
# shellcheck disable=SC2016 # Match the literal invocation in the script.
grep -F '"$agentchats_root/scripts/install.sh" --install' scripts/install.sh >/dev/null \
    || fail "installer does not invoke the agentchats contract"
# shellcheck disable=SC2016 # Match the literal invocation in the script.
grep -F '"$agentdesk_root/scripts/install.sh" --install' scripts/install.sh >/dev/null \
    || fail "installer does not invoke the agentdesk contract"

# The ownership boundary, from this side: Executor is the only desktop cask,
# and Grok Build is the only CLI-only cask this repository may install. The
# generic helper may mention the cask flag, but it must have exactly those two
# callers, and the unattended sync may never use it.
if grep -Eq -- '--cask' scripts/sync-skills; then
    fail "the unattended sync tried to install a Homebrew cask"
fi
# shellcheck disable=SC2016 # Match the literal generic helper variable.
if grep -E -- '--cask' scripts/install.sh \
    | grep -Ev 'executor|grok-build|"\$cask"' >/dev/null; then
    fail "an AgentStart script installs an unowned Homebrew cask"
fi
if [ "$(grep -Ec '^install_or_upgrade_cask ' scripts/install.sh)" -ne 2 ] \
    || ! grep -Fx 'install_or_upgrade_cask executor' scripts/install.sh >/dev/null \
    || ! grep -Fx 'install_or_upgrade_cask grok-build' scripts/install.sh >/dev/null; then
    fail "the installer does not own exactly the Executor and Grok Build casks"
fi
if grep -F 'oauth_token' scripts/install.sh >/dev/null; then
    fail "an AgentStart script crossed the boundary: gh migration is the machine's"
fi
# launchd is split rather than wholly the machine's: a bare <tool>.<service>
# label is a fleet service and this repository owns it; a reverse-DNS label is
# the machine's. The boundary that remains is the naming, so
# what is tested is that nothing here installs a machine-shaped service.
if grep -Eq '<string>(com|org|net)\.' config/launchd/*.plist; then
    fail "an AgentStart launch agent used a reverse-DNS label: machine services are not ours"
fi
# The updater path stays unattended-safe: sync-skills runs every six hours with
# no sudo and no service restarts, so it must never reach launchd.
if grep -Eq 'launchctl|\.plist' scripts/sync-skills; then
    fail "sync-skills must stay unattended-safe: launchd restarts do not belong there"
fi

# --- the fleet launch agents -------------------------------------------------

[ -x scripts/install-launchagents ] || fail "the launch agent installer is not executable"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-launchagents" --install' scripts/install.sh >/dev/null \
    || fail "installer does not converge the fleet launch agents"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-launchagents" --check' scripts/install.sh >/dev/null \
    || fail "installation plan omits the fleet launch agents"
# shellcheck disable=SC2016 # Match the literal non-mutating diagnostic invocation.
grep -F '"$script_dir/configure-agentsource-webhooks" --check || true' scripts/install.sh >/dev/null \
    || fail "ordinary install does not emit agent guidance for incomplete webhook wiring"
if rg -n 'agentbus\.(daemon|codex-appserver)' scripts/install-launchagents \
    config/launchd tests/validate.sh >/dev/null; then
    fail "retired AgentBus launch agents remain in the fleet service contract"
fi
[ ! -e config/launchd/agentweb.broker.plist ] \
    || fail "retired Agentweb broker template still exists"
if rg -n 'AGENTSCRAPE_CONDUIT|__CONDUIT_|agentweb_state' \
    scripts/install-launchagents config/launchd >/dev/null; then
    fail "retired Agentweb conduit wiring remains in the launch agent contract"
fi
grep -Fq "local label=agentweb.broker" scripts/install-launchagents \
    || fail "launch agent installer does not retire the canonical Agentweb broker label"
grep -Fq "agentstart-installer-owned: agentweb.broker.v1" scripts/install-launchagents \
    || fail "retired broker cleanup does not require the exact ownership marker"

expected_services='agentbrain.worker|agentbrain|worker.log|resident
agentbrain.share|agentbrain|share.log|resident
agentbrain.doctor|agentbrain|doctor.log|periodic
agentusage.observer|agentusage|observer.log|resident
agentattention.server|agentattention|server.log|resident
agentscrape.queue-processor|agentscrape|queue-processor.log|queue-triggered
agentsource.receiver|agentsource|receiver.log|resident
agentsource.notifier|agentsource|notifier.log|resident
agentwiki.server|agentwiki|server.log|resident'
for entry in $expected_services; do
    grep -Fq "\"$entry\"" scripts/install-launchagents \
        || fail "launch agent manifest omits canonical entry: $entry"
done
for legacy_binary in agentusaged agentwebd; do
    if sed -n '/^SERVICES=(/,/^)/p' scripts/install-launchagents | grep -Fq "$legacy_binary"; then
        fail "launch agent manifest still runs legacy daemon binary: $legacy_binary"
    fi
done

for template in config/launchd/*.plist; do
    label=$(basename "$template" .plist)
    # The marker is what lets the installer tell its own service from a
    # stranger's, so a template whose marker does not match its own file name
    # would either be refused forever or adopt something it should not.
    grep -Fq "agentstart-installer-owned: $label.v1" "$template" \
        || fail "template is missing or misnaming its ownership marker: $template"
    grep -Fq "<string>$label</string>" "$template" \
        || fail "template Label does not match its file name: $template"
    # Every value is rendered from the manifest; a per-tool token is a leftover
    # from the checkout this service was migrated out of.
    if grep -Eq '__[A-Z]+_(PROGRAM|HOME|PATH|LOG)__' "$template"; then
        fail "template still carries a per-tool token: $template"
    fi
    for required in '<key>Umask</key>' \
        '<key>StandardOutPath</key>' '<key>StandardErrorPath</key>'; do
        grep -Fq "$required" "$template" \
            || fail "template omits $required: $template"
    done
    # Correct at login, by one route or the other: started outright, or started
    # by launchd because the directory it watches is not empty.
    if ! grep -Eq '<key>(RunAtLoad|QueueDirectories)</key>' "$template"; then
        fail "template declares neither RunAtLoad nor QueueDirectories: $template"
    fi
    grep -Fq '<string>__LOG__</string>' "$template" \
        || fail "template does not log through the standard token: $template"
    # A service is either resident or periodic; one of the two must say so.
    if ! grep -Eq '<key>(KeepAlive|StartInterval)</key>' "$template"; then
        fail "template declares neither KeepAlive nor StartInterval: $template"
    fi
    if command -v plutil >/dev/null 2>&1; then
        plutil -lint "$template" >/dev/null || fail "template is not a valid plist: $template"
    fi
    grep -Fq "\"$label|" scripts/install-launchagents \
        || fail "template has no manifest entry: $template"
done

# And the reverse, so a manifest entry can never name a template that is not here.
# The service half of a label may be hyphenated (queue-processor),
# so both halves match hyphens too — a character class that stopped at [a-z] read
# straight past those entries and checked nothing.
while IFS= read -r label; do
    [ -f "config/launchd/$label.plist" ] \
        || fail "manifest names a service with no template: $label"
done < <(sed -n 's/^ *"\([a-z-]*\.[a-z-]*\)|.*/\1/p' scripts/install-launchagents)

grep -Fq '<string>webhook-daemon</string>' config/launchd/agentsource.receiver.plist \
    || fail "Agentsource receiver does not enter through the installed webhook-daemon subcommand"
grep -Fq '<string>notify-daemon</string>' config/launchd/agentsource.notifier.plist \
    || fail "Agentsource notifier does not enter through the installed notify-daemon subcommand"
# The notifier posts through terminal-notifier, which only the Homebrew prefix
# provides; a plist that hand-built PATH without it would run and never post.
grep -Fq '<string>__PATH__</string>' config/launchd/agentsource.notifier.plist \
    || fail "Agentsource notifier does not take the standard PATH that reaches terminal-notifier"
grep -Fq '<string>serve</string>' config/launchd/agentattention.server.plist \
    || fail "Agentattention server does not enter through the installed serve subcommand"
if grep -Eq '<key>[^<]*(TOKEN|SECRET)[^<]*</key>' config/launchd/agentattention.server.plist; then
    fail "Agentattention server rendered a credential-shaped environment variable"
fi
grep -Fq '<string>__SECRET_FILE__</string>' config/launchd/agentsource.receiver.plist \
    || fail "Agentsource receiver does not name the private secret by path"
grep -A1 -F '<string>--port</string>' config/launchd/agentsource.receiver.plist \
    | grep -Fq '<string>8787</string>' \
    || fail "Agentsource receiver does not pin its Funnel-coupled HTTP port"
if grep -Eq '<key>[^<]*SECRET[^<]*</key>' config/launchd/agentsource.receiver.plist; then
    fail "Agentsource receiver rendered a credential-shaped environment variable"
fi

printf 'ok\n'
