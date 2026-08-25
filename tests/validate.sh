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
scripts/render-capabilities
scripts/install-agent-clis
scripts/install-agentlaunch-shims
scripts/install-agentvoice-cli
scripts/remove-retired-integrations
scripts/install-launchagents
scripts/fmx-config
scripts/herdr-config
tests/validate.sh
tests/fmx-config.sh
tests/herdr-config.sh
tests/fixtures/npx
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

for script in scripts/install.sh scripts/sync-skills scripts/install-agent-clis \
    scripts/install-agentlaunch-shims scripts/render-capabilities scripts/install-launchagents \
    scripts/render-skill-invocation-policy \
    scripts/install-agentvoice-cli scripts/remove-retired-integrations \
    scripts/fmx-config scripts/herdr-config; do
    [ -x "$script" ] || fail "installer script is not executable: $script"
done
[ -x tests/fmx-config.sh ] \
    || fail "fmx config test is not executable: tests/fmx-config.sh"
[ -x tests/herdr-config.sh ] \
    || fail "Herdr config test is not executable: tests/herdr-config.sh"
[ -x scripts/remove-retired-json-hooks.ts ] \
    || fail "retired JSON hook cleanup helper is not executable"
for supervisor_script in \
    skills/supervisor/scripts/watch.ts \
    skills/supervisor/scripts/integrate.ts \
    skills/supervisor/scripts/reap.ts \
    skills/supervisor/scripts/status.ts; do
    [ -x "$supervisor_script" ] \
        || fail "supervisor helper is not executable: $supervisor_script"
done

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

for manifest in config/capabilities/common/*.json; do
    /usr/bin/jq -e . "$manifest" >/dev/null \
        || fail "capability manifest is not valid JSON: $manifest"
done
/usr/bin/jq -e '.schema_version == 1 and .id == "common" and .default == true' \
    config/capabilities/common/capability.json >/dev/null \
    || fail "common capability manifest has the wrong identity or default"
/usr/bin/jq -e '.name == "agent"' config/capabilities/common/claude-plugin.json >/dev/null \
    || fail "Claude session projection has the wrong plugin name"
/usr/bin/jq -e '.name == "agent"' config/capabilities/common/codex-plugin.json >/dev/null \
    || fail "Codex compatibility projection has the wrong plugin name"
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

# The voice server configuration is linked into ~/.config/agentvoice and
# read once at server boot; a missing or empty file primes nothing, silently.
# The orchestrator doctrine no longer lives here: agentguidance renders it
# to ~/.agents/prompts/agentvoice, and the installer links that — after
# sync-skills, so the rendered source exists before the link is checked.
[ -s prompts/agentvoice/server.json ] \
    || fail "AgentVoice server configuration is missing or empty: prompts/agentvoice/server.json"
/usr/bin/jq -e . prompts/agentvoice/server.json >/dev/null \
    || fail "AgentVoice server.json is not valid JSON"
for doctrine in ORCHESTRATOR.md ORCHESTRATOR_SESSION_START.md; do
    [ ! -e "prompts/agentvoice/$doctrine" ] \
        || fail "AgentVoice orchestrator doctrine belongs to agentguidance now: prompts/agentvoice/$doctrine"
done
# shellcheck disable=SC2016 # Match the literal rendered-doctrine path in the script.
grep -F 'rendered_dir="$HOME/.agents/prompts/agentvoice"' scripts/install.sh >/dev/null \
    || fail "install.sh does not link the rendered AgentVoice doctrine"
voice_link_line=$(grep -n '^link_agentvoice_config$' scripts/install.sh | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal sync-skills call, $-sign and all.
sync_skills_line=$(grep -n '^"$script_dir/sync-skills"$' scripts/install.sh | cut -d: -f1)
[ -n "$voice_link_line" ] && [ -n "$sync_skills_line" ] \
    && [ "$voice_link_line" -gt "$sync_skills_line" ] \
    || fail "link_agentvoice_config must run after sync-skills renders the doctrine"

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
grep -q 'allow_implicit_invocation: true' skills/fleet/agents/openai.yaml \
    || fail "the fleet skill manifest does not allow implicit invocation"
[ -s skills/fleet/MAP.md ] \
    || fail "the fleet dependency map is missing: skills/fleet/MAP.md"
grep -q '```mermaid' skills/fleet/MAP.md \
    || fail "the fleet dependency map has no mermaid diagram"
if grep -F '../' skills/fleet/SKILL.md >/dev/null; then
    fail "the fleet skill reaches outside its own directory and would ship broken"
fi

# The supervisor is a portable skill with executable mechanics: its watcher
# carries the Herdr reconnect/reconcile contract and its integrator guards the
# exact commit that may move main, while its reaper preserves branch identity.
# Exercise them against disposable repositories and a fake socket rather than
# accepting prose-only coverage.
[ -f skills/supervisor/SKILL.md ] \
    || fail "the supervisor skill is missing: skills/supervisor/SKILL.md"
grep -q '^name: supervisor$' skills/supervisor/SKILL.md \
    || fail "the supervisor skill frontmatter does not name /supervisor"
[ -f skills/supervisor/agents/openai.yaml ] \
    || fail "the supervisor skill is missing its agents/openai.yaml manifest"
grep -q 'allow_implicit_invocation: true' skills/supervisor/agents/openai.yaml \
    || fail "the supervisor skill manifest does not allow implicit invocation"
command -v bun >/dev/null 2>&1 \
    || fail "bun is required to test the supervisor's TypeScript helpers"
bun test tests/supervisor.test.ts

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

# A machine that has not cloned AgentVoice is a skip, not a failure: the CLI is
# one of several optional checkout-backed tools and an install must not stop
# for a machine that simply does not have it.
skip_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-validate.XXXXXX")
trap 'rm -rf "$skip_test_dir"' EXIT
agentvoice_missing_home="$skip_test_dir/agentvoice-missing-home"
mkdir -p "$agentvoice_missing_home"
set +e
agentvoice_missing_output=$(
    HOME="$agentvoice_missing_home" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        "$root/scripts/install-agentvoice-cli" 2>&1
)
agentvoice_missing_status=$?
set -e
[ "$agentvoice_missing_status" -eq 0 ] \
    || fail "AgentVoice CLI installer did not skip a machine without a checkout"
printf '%s\n' "$agentvoice_missing_output" \
    | grep -F \
        "no checkout at $agentvoice_missing_home/code/agentvoice; skipping." \
        >/dev/null \
    || fail "AgentVoice CLI installer did not report the skipped checkout clearly"

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
for shim_harness in claude codex pi; do
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
for shim_harness in claude codex pi; do
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

# Retired integrations are removed only when they carry exact AgentStart or
# predecessor-owned markers. Independent files that merely live at old paths
# must survive.
cleanup_home="$skip_test_dir/cleanup-home"
cleanup_code_root="$skip_test_dir/cleanup-code"
mkdir -p \
    "$cleanup_home/.local/bin" \
    "$cleanup_home/.local/share/agentsurface/shims" \
    "$cleanup_home/.pi/agent/extensions" \
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
    "$cleanup_code_root/agentbus/extensions/pi" \
    "$cleanup_code_root/agentbus/plugins/claude" \
    "$cleanup_code_root/agentsurface/src"
touch \
    "$cleanup_code_root/agentbus/src/main.ts" \
    "$cleanup_code_root/agentbus/extensions/pi/agentbus.ts" \
    "$cleanup_code_root/agentbus/plugins/claude/.keep" \
    "$cleanup_code_root/agentsurface/src/main.ts"
ln -s "$cleanup_code_root/agentbus/src/main.ts" "$cleanup_home/.local/bin/agentbus"
ln -s "$cleanup_code_root/agentsurface/src/main.ts" "$cleanup_home/.local/bin/agentsurface"
ln -s "$cleanup_code_root/agentbus/extensions/pi/agentbus.ts" "$cleanup_home/.pi/agent/extensions/agentbus.ts"
ln -s "$cleanup_code_root/agentbus/plugins/claude" "$cleanup_home/.claude/skills/agentbus"
printf '# AgentStart-managed agentsurface shim: old\n' \
    >"$cleanup_home/.local/share/agentsurface/shims/claude"
printf '# independent shim\n' \
    >"$cleanup_home/.local/share/agentsurface/shims/codex"
printf '// @orca-managed-pi-extension\n' \
    >"$cleanup_home/.pi/agent/extensions/orca-agent-status.ts"
printf '// independent extension\n' \
    >"$cleanup_home/.pi/agent/extensions/orca-prefill.ts"
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
[ ! -e "$cleanup_home/.pi/agent/extensions/agentbus.ts" ] \
    || fail "retired AgentBus Pi extension was not removed"
[ ! -e "$cleanup_home/.claude/skills/agentbus" ] \
    || fail "retired AgentBus Claude plugin was not removed"
[ ! -e "$cleanup_home/.local/share/agentsurface/shims/claude" ] \
    || fail "retired AgentSurface shim was not removed"
[ -e "$cleanup_home/.local/share/agentsurface/shims/codex" ] \
    || fail "independent shim at old AgentSurface path was removed"
[ ! -e "$cleanup_home/.pi/agent/extensions/orca-agent-status.ts" ] \
    || fail "retired Orca Pi extension was not removed"
[ -e "$cleanup_home/.pi/agent/extensions/orca-prefill.ts" ] \
    || fail "independent Pi extension was removed"
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

# The agent* skill scan finds participants by convention instead of by list:
# an agent* checkout that exports skills/<name>/SKILL.md is a participant, and
# everything else under the root is not. The scan must batch one invocation
# per project naming every skill it found, and no participant is exempt.
code_skills_root="$skip_test_dir/code-root"
code_skills_home="$skip_test_dir/code-home"
code_skills_log="$skip_test_dir/npx.log"
mkdir -p \
    "$code_skills_home" \
    "$code_skills_home/.pi/agent/extensions" \
    "$code_skills_root/agentbus/skills/bus" \
    "$code_skills_root/agentdemo/skills/demo" \
    "$code_skills_root/agentdemo/skills/second" \
    "$code_skills_root/agentquiet/src" \
    "$code_skills_root/agentretired/skills/orchestration" \
    "$code_skills_root/agentvoice/skills/story" \
    "$code_skills_root/notagent/skills/x"
for code_skills_fixture in \
    agentbus/skills/bus \
    agentdemo/skills/demo \
    agentdemo/skills/second \
    agentretired/skills/orchestration \
    agentvoice/skills/story \
    notagent/skills/x; do
    code_skills_name=${code_skills_fixture##*/}
    printf -- '---\nname: %s\ndescription: fixture skill\n---\n' "$code_skills_name" \
        >"$code_skills_root/$code_skills_fixture/SKILL.md"
done
# The portable frontmatter is the invocation-policy source of truth. This
# skill deliberately has no OpenAI manifest; the renderer must create one.
sed -i '' '/^description:/a\
disable-model-invocation: true
' "$code_skills_root/agentdemo/skills/second/SKILL.md"
cat >"$code_skills_home/.pi/agent/extensions/herdr-agent-state.ts" <<'EOF'
// installed by herdr
// managed by herdr; reinstalling or updating the integration overwrites this file.
// HERDR_INTEGRATION_ID=pi
export {};
EOF
# OpenAI manifests are portable source: their default prompt starts with the
# plain skill name. Compatibility packaging must qualify only its generated
# copy without changing the canonical common pack.
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
    | grep -F "npx --yes skills add \"$code_skills_root/agentvoice\" --agent claude-code --skill story --global --copy --yes" \
        >/dev/null \
    || fail "skill sync plan exempts AgentVoice instead of scanning it like any other participant"
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

# The Pi subagent package the full installer pins. The renderer only carries an
# install that is already present, so the fixture stands in for one.
fixture_pi_subagents_root="$code_skills_home/pi-subagents-install"
mkdir -p \
    "$fixture_pi_subagents_root/pi-subagents/node_modules/yaml" \
    "$fixture_pi_subagents_root/pi-subagents/skills/pi-subagents" \
    "$fixture_pi_subagents_root/pi-subagents/prompts"
cat >"$fixture_pi_subagents_root/pi-subagents/package.json" <<'FIXTURE_JSON'
{
  "name": "pi-subagents",
  "version": "9.9.9",
  "pi": { "extensions": ["./index.ts"], "skills": ["./skills"], "prompts": ["./prompts"] }
}
FIXTURE_JSON
printf 'export default () => {}\n' \
    >"$fixture_pi_subagents_root/pi-subagents/index.ts"
printf '{"name":"yaml"}\n' \
    >"$fixture_pi_subagents_root/pi-subagents/node_modules/yaml/package.json"
printf -- '---\nname: pi-subagents\ndescription: fixture\n---\n' \
    >"$fixture_pi_subagents_root/pi-subagents/skills/pi-subagents/SKILL.md"
printf -- '---\ndescription: fixture workflow\n---\n' \
    >"$fixture_pi_subagents_root/pi-subagents/prompts/parallel-review.md"

HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" \
    AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
    AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
    AGENTSTART_CLAUDE_BIN=/usr/bin/true \
    AGENTSTART_CODEX_BIN=/usr/bin/true \
    AGENTSTART_PI_SUBAGENTS_ROOT="$fixture_pi_subagents_root" \
    "$root/scripts/sync-skills" >/dev/null
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentdemo> <--agent> <claude-code> <--skill> <demo> <second> <--global> <--copy> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync did not ship both discovered skills in one invocation"
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentvoice> <--agent> <claude-code> <--skill> <story> <--global> <--copy> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync skipped AgentVoice instead of synchronizing it"
if grep -E 'agentquiet|notagent' "$code_skills_log" >/dev/null; then
    fail "skill sync synchronized a checkout that is not a participant"
fi
grep -F "npx-stub <--yes> <skills> <add> <$code_skills_root/agentbus> <--agent> <claude-code> <--skill> <bus> <--global> <--copy> <--yes>" \
    "$code_skills_log" >/dev/null \
    || fail "skill sync skipped the bus skill, back in service since 2026-08-17"
if grep -E 'agentretired|orchestration' "$code_skills_log" >/dev/null; then
    fail "skill sync re-added a retired skill"
fi
# One invocation each for agentbus, agentdemo, and agentvoice.
[ "$(grep -c 'skills> <add>' "$code_skills_log")" -eq 3 ] \
    || fail "skill sync did not invoke the skills tool exactly once per source"
[ -e "$code_skills_root/agentdemo/post-sync-ran" ] \
    || fail "skill sync did not run a participant's post-sync hook after its skills landed"
fixture_capabilities_root="$code_skills_home/.local/share/agentstart/capabilities"
fixture_common_root="$fixture_capabilities_root/packs/common"
fixture_claude_root="$fixture_capabilities_root/projections/common/claude/agent"
fixture_codex_root="$fixture_capabilities_root/compatibility/codex-marketplace/plugins/agent"
[ -f "$fixture_common_root/skills/demo/SKILL.md" ] \
    || fail "skill sync did not copy a participant into the common capability pack"
[ -f "$fixture_common_root/capability.json" ] \
    || fail "skill sync did not render the common capability manifest"
[ -f "$fixture_claude_root/.claude-plugin/plugin.json" ] \
    || fail "skill sync did not render the Claude session projection"
[ -f "$fixture_codex_root/.codex-plugin/plugin.json" ] \
    || fail "skill sync did not render the Codex compatibility projection"
# shellcheck disable=SC2016 # Match the literal Codex plugin-qualified skill reference.
grep -F 'default_prompt: "Use $agent:demo with this fixture."' \
    "$fixture_codex_root/skills/demo/agents/openai.yaml" >/dev/null \
    || fail "the compatibility projection did not qualify demo's Codex default prompt"
# shellcheck disable=SC2016 # Match the literal portable source skill reference.
grep -F 'default_prompt: "Use $demo with this fixture."' \
    "$fixture_common_root/skills/demo/agents/openai.yaml" >/dev/null \
    || fail "Codex prompt qualification changed the canonical pack manifest"
grep -F 'allow_implicit_invocation: true' \
    "$fixture_common_root/skills/demo/agents/openai.yaml" >/dev/null \
    || fail "the renderer did not replace stale Codex policy from canonical frontmatter"
[ ! -w "$fixture_common_root/skills/demo/agents/openai.yaml" ] \
    || fail "the invocation-policy renderer changed a read-only manifest's mode"
grep -F 'allow_implicit_invocation: false' \
    "$fixture_common_root/skills/second/agents/openai.yaml" >/dev/null \
    || fail "the renderer did not create Codex policy for an explicit-only skill"
"$root/scripts/render-skill-invocation-policy" --check \
    "$fixture_common_root/skills" >/dev/null \
    || fail "the rendered common pack does not pass its invocation-policy audit"
# The audit is independently useful: prove it rejects drift instead of merely
# agreeing with the renderer that just ran.
sed -i '' 's/allow_implicit_invocation: true/allow_implicit_invocation: false/' \
    "$fixture_common_root/skills/demo/agents/openai.yaml"
if "$root/scripts/render-skill-invocation-policy" --check \
    "$fixture_common_root/skills" >/dev/null 2>&1; then
    fail "the invocation-policy audit accepted drift from canonical frontmatter"
fi
"$root/scripts/render-skill-invocation-policy" --install \
    "$fixture_common_root/skills" >/dev/null
chmod 644 "$fixture_common_root/skills/demo/agents/openai.yaml"
[ ! -e "$code_skills_home/.pi/agent/skills/demo" ] \
    || fail "skill sync leaked a common skill into Pi's ambient global root"
[ -f "$fixture_common_root/pi/extensions/herdr-agent-state.ts" ] \
    || fail "skill sync did not collect Pi's generated Herdr extension into common"
[ -f "$code_skills_home/.pi/agent/extensions/herdr-agent-state.ts" ] \
    || fail "unattended skill sync removed Pi's ambient Herdr extension"
cmp -s \
    "$code_skills_home/.pi/agent/extensions/herdr-agent-state.ts" \
    "$fixture_common_root/pi/extensions/herdr-agent-state.ts" \
    || fail "skill sync did not copy Pi's Herdr extension exactly into common"

# The subagent package rides the pack as a directory, because AgentLaunch names
# a directory with --extension and Pi reads the manifest inside it to register
# the extension, its skills, and its workflow templates from that one path.
fixture_pi_subagents_packed="$fixture_common_root/pi/extensions/pi-subagents"
[ -f "$fixture_pi_subagents_packed/package.json" ] \
    || fail "skill sync did not carry the Pi subagent package into common"
grep -F '"pi":' "$fixture_pi_subagents_packed/package.json" >/dev/null \
    || fail "the packed Pi subagent package lost the manifest Pi resolves it by"
# Pi never installs dependencies for a local path, and AgentLaunch projects an
# entry by copying its own subtree, so the dependencies must ride inside it.
[ -f "$fixture_pi_subagents_packed/node_modules/yaml/package.json" ] \
    || fail "the packed Pi subagent package lost its runtime dependencies"
[ -f "$fixture_pi_subagents_packed/prompts/parallel-review.md" ] \
    || fail "the packed Pi subagent package lost its workflow prompt templates"
[ -f "$fixture_pi_subagents_packed/skills/pi-subagents/SKILL.md" ] \
    || fail "the packed Pi subagent package lost its own skills"
[ ! -e "$code_skills_home/.pi/agent/extensions/pi-subagents" ] \
    || fail "skill sync installed the Pi subagent package into Pi's ambient root"

# A matching version is a no-op: this is the one pack resource large enough
# that re-copying it every six hours would be felt.
printf 'sentinel\n' >"$fixture_pi_subagents_packed/render-sentinel"
HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" \
    AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
    AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
    AGENTSTART_CLAUDE_BIN=/usr/bin/true \
    AGENTSTART_CODEX_BIN=/usr/bin/true \
    AGENTSTART_PI_SUBAGENTS_ROOT="$fixture_pi_subagents_root" \
    "$root/scripts/sync-skills" >/dev/null
[ -f "$fixture_pi_subagents_packed/render-sentinel" ] \
    || fail "the renderer re-copied an unchanged Pi subagent package"

# A newer pin replaces the packed copy wholesale.
/usr/bin/sed -i '' 's/"9.9.9"/"9.9.10"/' \
    "$fixture_pi_subagents_root/pi-subagents/package.json"
HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" \
    AGENTSTART_NPX_BIN="$root/tests/fixtures/npx" \
    AGENTSTART_TEST_NPX_LOG="$code_skills_log" \
    AGENTSTART_CLAUDE_BIN=/usr/bin/true \
    AGENTSTART_CODEX_BIN=/usr/bin/true \
    AGENTSTART_PI_SUBAGENTS_ROOT="$fixture_pi_subagents_root" \
    "$root/scripts/sync-skills" >/dev/null
[ ! -e "$fixture_pi_subagents_packed/render-sentinel" ] \
    || fail "the renderer kept a stale Pi subagent package across a version change"
grep -F '"9.9.10"' "$fixture_pi_subagents_packed/package.json" >/dev/null \
    || fail "the renderer did not carry the newer Pi subagent pin into common"
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

# shellcheck disable=SC2016 # Match the exclusion guard the scan must not have.
if grep -F '[ "$project_name" != agentvoice ] || continue' scripts/sync-skills >/dev/null; then
    fail "the skill scan exempts AgentVoice by name"
fi

# The installation plan embeds the skill sync's own plan, pointed at the
# fixture tree so the asserted lines are the same on every machine.
install_plan=$(HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" "$root/scripts/install.sh" --check)
# shellcheck disable=SC2016,SC2088 # Plan lines are literal, including $ and ~.
for required_install in \
    'curl -fsSL https://claude.ai/install.sh | bash' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'curl -fsSL https://pi.dev/install.sh | sh  # in its own session, no controlling terminal' \
    'brew install or upgrade zig  # AgentVoice'"'"'s native duplex audio path builds against it' \
    '~/code/fxnk/scripts/install.sh --install  # fxnk owns the published fork/integration build and disables auto-upgrade' \
    'brew install or upgrade llm  # an AI CLI, so AgentStart'"'"'s outright — moved out of the machine'"'"'s Brewfile' \
    'brew install or upgrade hunk  # review-first diff TUI whose bundled agent skill follows the installed build' \
    'brew install or upgrade rustup  # Terminal Control builds from crates.io with the current stable Rust toolchain' \
    'brew install or upgrade zig@0.15  # herdr'"'"'s vendored libghostty-vt pins the 0.15 line; keg-only beside the tracked zig' \
    '"$(brew --prefix rustup)/bin/rustup" toolchain install stable --profile minimal' \
    'PATH="$(brew --prefix)/opt/zig@0.15/bin:$PATH" "$(brew --prefix rustup)/bin/rustup" run stable cargo install --locked --root "$HOME/.local" terminal-control' \
    'scripts/update-herdr  # herdr from the bound ~/src/herdr checkout: fast-forward clean master, build, install to ~/.local/bin; blocked checkouts notify instead of forcing' \
    'brew uninstall herdr if the formula lingers  # retired: it would shadow the checkout build on PATH' \
    'herdr integration install claude, codex, and pi  # Claude and Codex are pinned to canonical ~/.claude and ~/.codex, and stale swap-session hooks are pruned' \
    'bun install --frozen-lockfile and bun link in ~/code/fmx  # global editable fmx: ~/.bun/bin/fmx runs the checkout'"'"'s src/index.ts, so edits are live' \
    '~/code/fmx/scripts/install-companion.sh  # the pinned fmx-zmx Companion into ~/.local/bin, built from ~/src/zmx; a no-op while it already reports the pin' \
    'scripts/fmx-config install  # link the Herdr-compatible fmx key subset with the operator'"'"'s Ctrl-Space prefix' \
    'scripts/herdr-config install  # render, validate, and activate the generated Herdr config, then reload it' \
    'remove AgentStart-owned ~/Library/Application Support/io.datasette.llm/extra-openai-models.yaml symlink  # its extra model records are obsolete' \
    'remove ownership-verified AgentSurface, AgentBus, and Orca harness integrations' \
    'remove AgentStart-managed skills from Fx-visible compatibility roots, including retired livekit-simulations  # full install only; independent occupants are preserved' \
    'npm install --global @native-sdk/cli@0.7  # the line the native-sdk skill documents' \
    'npm install --global agent-browser@0.33.2  # Agentweb'"'"'s config.json digest-locks this exact build' \
    'ln -sfn "$(command -v agent-browser)" ~/.local/bin/agent-browser  # the candidate Agentscrape resolves before PATH' \
    'codex mcp add shadcn -- npx shadcn@latest mcp' \
    'claude mcp add --scope user shadcn -- npx shadcn@latest mcp' \
    'native skills list' \
    'ln -sfn ~/.local/share/agentstart/capabilities/packs/common/guidance/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md' \
    'ln -sfn ~/.local/share/agentstart/capabilities/packs/common/guidance/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files' \
    'ln -sfn ~/.local/share/agentstart/capabilities/packs/common/guidance/AGENTS.md ~/.pi/agent/AGENTS.md  # pi'"'"'s global slot' \
    'remove AgentStart-owned ~/AGENTS.md symlink  # retired hub; independent occupants are preserved' \
    'ln -sfn prompts/agentvoice/server.json into ~/.config/agentvoice  # the voice server configuration, read at server boot' \
    'ln -sfn ~/.agents/prompts/agentvoice/{ORCHESTRATOR.md,ORCHESTRATOR_SESSION_START.md} into ~/.config/agentvoice  # the voice orchestrator'"'"'s doctrine; agentguidance renders it, so this links after sync-skills' \
    'ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES,TOOLS}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against' \
    'install external skill packs with --copy into ~/.local/share/agentstart/capabilities/packs/common/skills' \
    'https://github.com/vercel-labs/skills: find-skills' \
    'https://github.com/anthropics/skills: frontend-design' \
    'https://github.com/vercel-labs/agent-skills: web-design-guidelines, vercel-react-best-practices' \
    'https://github.com/vercel/ai: ai-sdk' \
    'https://github.com/vercel/ai-elements: ai-elements' \
    'https://github.com/shadcn/ui: shadcn' \
    'https://github.com/vercel-labs/native: native-sdk' \
    'anomalyco/terminal-control@v<installed termctrl version>: terminal-control' \
    'hunk skill path hunk-review  # the review skill ships inside the binary and stays version-matched to it' \
    'install hunk-review with --copy into the common capability pack' \
    'herdr --skill, rendered to ~/.local/share/agentstart/herdr-skill/skills/herdr/SKILL.md  # the surface skill ships inside the binary, so it converges with the installed build, never a stale copy' \
    'install herdr with --copy into the common capability pack' \
    'render one session-only Claude plugin named agent (/agent:<skill>)' \
    'render and refresh the temporary Codex desktop compatibility plugin agent@agentstart-managed' \
    'leave retired-plugin and ambient-link cleanup to the explicit full installer' \
    "npx --yes skills add \"$code_skills_root/agentdemo\" --agent claude-code --skill demo second --global --copy --yes" \
    "\"$code_skills_root/agentdemo/scripts/post-sync\""; do
    printf '%s\n' "$install_plan" | grep -F "$required_install" >/dev/null \
        || fail "installation plan is missing: $required_install"
done

# Fx remains a required harness, but fxnk owns its fork and installer. This
# repository invokes the public contract and carries no second implementation.
# shellcheck disable=SC2016 # Match the literal configurable code-root contract.
grep -F 'fxnk_installer="$code_root/fxnk/scripts/install.sh"' scripts/install.sh >/dev/null \
    || fail "installer does not resolve fxnk's Fx installation contract"
# shellcheck disable=SC2016 # Match the literal installer variable invocation.
grep -F '"$fxnk_installer" --install' scripts/install.sh >/dev/null \
    || fail "installer does not invoke fxnk's Fx installation contract"
[ ! -e scripts/install-fx ] \
    || fail "AgentStart retains a second Fx installer"
if grep -F 'https://fx.sh/setup.sh' scripts/install.sh >/dev/null; then
    fail "installer retains the official Fx bootstrap beside the integration build"
fi
if grep -F 'upgrade --channel dev' scripts/install.sh >/dev/null; then
    fail "installer retains the Fx dev channel beside the integration build"
fi
# shellcheck disable=SC2016 # Assert the literal environment pin in the installer.
grep -F 'CODEX_HOME="$HOME/.codex" herdr integration install "$harness"' \
    scripts/install.sh >/dev/null \
    || fail "Herdr's Codex integration can inherit a disposable multi-auth CODEX_HOME"
grep -F "codex-multi-auth-runtime-home-[^/']+/herdr-agent-state\\.sh" \
    scripts/install.sh >/dev/null \
    || fail "installer does not prune stale Codex multi-auth Herdr hook definitions"
# shellcheck disable=SC2016 # Assert the literal environment pin in the installer.
grep -F 'CLAUDE_CONFIG_DIR="$HOME/.claude" herdr integration install "$harness"' \
    scripts/install.sh >/dev/null \
    || fail "Herdr's Claude integration can inherit a claude-swap session CLAUDE_CONFIG_DIR"
grep -F "/\\.claude-swap-backup/sessions/" \
    scripts/install.sh >/dev/null \
    || fail "installer does not prune stale Claude swap-session Herdr hook definitions"
printf '%s\n' "$install_plan" | grep -F 'retired livekit-simulations' >/dev/null \
    || fail "installation plan no longer scrubs the retired LiveKit skill"
# AgentVoice exports skills/ like the other agent tools and is scanned like
# them; nothing about it is special to this plan.
printf '%s\n' "$install_plan" \
    | grep -F "skills add \"$code_skills_root/agentvoice\"" >/dev/null \
    || fail "installation plan omits the skills AgentVoice exports by convention"
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
# The ownership boundary: desktop applications and the GitHub CLI belong to the
# machine layer, so a cask or gh line here means the seam is leaking back.
if printf '%s\n' "$install_plan" | grep -Eq -- '--cask|brew install or upgrade gh'; then
    fail "installation plan crossed the boundary: desktop casks and gh are the machine's"
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
grep -F '"$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"' scripts/install.sh >/dev/null \
    || fail "installer does not target all three harness guidance locations"
grep -F 'refusing to replace independent guidance' scripts/install.sh >/dev/null \
    || fail "installer would replace independent guidance files"
# shellcheck disable=SC2016 # Match the literal direct-link operation.
grep -F 'ln -sfn "$source" "$target"' scripts/install.sh >/dev/null \
    || fail "installer does not link each harness slot directly to the guidance source"
if grep -F 'home_guidance=' scripts/install.sh >/dev/null \
    || grep -F 'ln -sfn prompts/AGENTS.md ~/AGENTS.md' scripts/install.sh >/dev/null; then
    fail "installer still creates the retired home guidance hub"
fi
grep -q '^remove_retired_home_guidance$' scripts/install.sh \
    || fail "installer does not remove its retired home guidance symlink"
grep -F 'link_extension_prompts' scripts/install.sh >/dev/null \
    || fail "installer does not link the operator extension prompts"
grep -F 'refusing to replace independent extension prompt' scripts/install.sh >/dev/null \
    || fail "installer would replace an independent extension prompt"
for prompt_name in SYSTEM.md GUIDELINES.md TOOLS.md; do
    grep -F "$prompt_name" scripts/install.sh >/dev/null \
        || fail "installer does not link the $prompt_name extension prompt"
done
grep -F 'link_agentvoice_config' scripts/install.sh >/dev/null \
    || fail "installer does not link the AgentVoice doctrine"
grep -F 'refusing to replace independent AgentVoice configuration' scripts/install.sh >/dev/null \
    || fail "installer would replace independent AgentVoice configuration"
for doctrine_name in ORCHESTRATOR.md ORCHESTRATOR_SESSION_START.md server.json; do
    grep -F "$doctrine_name" scripts/install.sh >/dev/null \
        || fail "installer does not link the AgentVoice $doctrine_name"
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

# The native-sdk skill documents the 0.7 line and Zig builds both Native SDK
# applications and AgentVoice's opt-in native duplex audio device, so both
# stay pinned rather than tracking latest. agent-browser is pinned because
# Agentweb digest-locks the exact build in its config.json.
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
# common capability pack to Claude Code, Codex, and Pi.
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
    || fail "installer does not converge the locked Terminal Control crate into ~/.local/bin"
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

# herdr is bound to the ~/src/herdr checkout at upstream master and
# update-herdr is its one update path — fast-forward a clean checkout, build
# with the pinned Zig, install to ~/.local/bin — so the retired formula and
# the direct installer must both stay out. Its integrations reinstall
# unconditionally because a herdr upgrade can stale them, and they cover
# exactly the three harnesses the fleet runs.
# shellcheck disable=SC2016 # Match the literal invocation in the installer.
grep -F '"$script_dir/update-herdr"' scripts/install.sh >/dev/null \
    || fail "installer does not converge herdr from the bound checkout"
[ -x scripts/update-herdr ] \
    || fail "update-herdr is missing or not executable"
grep -F -- '--ff-only' scripts/update-herdr >/dev/null \
    || fail "update-herdr does not restrict itself to fast-forwarding the checkout"
grep -F 'install_or_upgrade_formula zig@0.15' scripts/install.sh >/dev/null \
    || fail "installer does not converge the Zig 0.15 line herdr builds against"
if grep -F 'install_or_upgrade_formula herdr' scripts/install.sh >/dev/null; then
    fail "installer resurrects the retired herdr formula beside the checkout build"
fi
# Anchored to an invocation, not any mention: comments may name `herdr update`
# to explain why it stays unused.
if grep -E '^[[:space:]]*herdr update' scripts/install.sh >/dev/null; then
    fail "installer grows a second herdr update path beside update-herdr"
fi
if grep -F 'herdr.dev/install.sh' scripts/install.sh >/dev/null; then
    fail "installer uses the direct herdr installer instead of the checkout build"
fi
grep -F 'install_herdr_integrations' scripts/install.sh >/dev/null \
    || fail "installer does not converge the herdr harness integrations"
grep -F 'for harness in claude codex pi' scripts/install.sh >/dev/null \
    || fail "herdr integrations do not cover the three harnesses the fleet runs"

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
grep -F 'plugin pane open --plugin agentsurface --entrypoint voice' \
    config/herdr/config.toml >/dev/null \
    || fail "agentvoice binding does not open its AgentSurface plugin pane"
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
[ "$sidebar_settings" = 'sidebar_max_width = 106' ] \
    || fail "Herdr sidebar does not keep only its 50%-of-screen width allowance"
if grep -E '^((agent_panel_sort|status_indicators) = |\[ui\.sidebar\.)' \
    config/herdr/config.toml >/dev/null; then
    fail "Herdr config still customizes the left sidebar beyond its width allowance"
fi
grep -F 'delivery = "system"' config/herdr/config.toml >/dev/null \
    || fail "Herdr notifications do not use the terminal-notifier-backed system delivery"
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
# fmx installs editable: a frozen dependency install plus bun link, so the
# global command runs the checkout source directly.
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F 'bun install --cwd "$fmx_root" --frozen-lockfile' scripts/install.sh >/dev/null \
    || fail "installer does not install fmx dependencies frozen"
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F '(cd "$fmx_root" && bun link)' scripts/install.sh >/dev/null \
    || fail "installer does not bun-link fmx editable"
# An editable fmx needs the Companion its companion.json pins on PATH; fmx's
# own script builds and places it, and the installer never builds it by hand.
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F '"$fmx_root/scripts/install-companion.sh"' scripts/install.sh >/dev/null \
    || fail "installer does not install fmx's pinned Companion"
if grep -F 'Dcompanion' scripts/install.sh >/dev/null; then
    fail "installer builds the Companion by hand instead of through fmx's script"
fi
# fmx's config is linked because fmx does not mutate it; both the tracked source
# and the installer stay pinned to the same Ctrl-Space prefix used by Herdr.
grep -Fqx 'prefix = "ctrl+space"' config/fmx/config.toml \
    || fail "fmx config does not use the operator's Ctrl-Space prefix"
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F '"$script_dir/fmx-config" install' scripts/install.sh >/dev/null \
    || fail "installer does not link the fmx config"
tests/fmx-config.sh

# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F '"$script_dir/herdr-config" install' scripts/install.sh >/dev/null \
    || fail "installer does not render the Herdr config"
tests/herdr-config.sh

# The AgentSurface popup-pane and tab-naming plugin registers by checkout path;
# linking every run is the converge, and a missing agentsurface checkout is a
# skip, not a failure.
grep -F 'install_herdr_plugins' scripts/install.sh >/dev/null \
    || fail "installer does not link the agentsurface herdr plugin"
# shellcheck disable=SC2016 # Match the literal link invocation, $-sign and all.
grep -F 'herdr plugin link "$plugin_root"' scripts/install.sh >/dev/null \
    || fail "the agentsurface plugin is not registered by checkout path"
# The surface skill ships inside the binary (`herdr --skill`) and converges
# with the installed build; a GitHub-sourced copy would track a different
# head than the installed herdr and grow a second update path.
grep -F 'install_herdr_skill' scripts/install.sh >/dev/null \
    || fail "installer does not converge the herdr surface skill"
grep -F 'herdr --skill' scripts/install.sh >/dev/null \
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
    || fail "installer does not copy Hunk's bundled review skill into the common capability pack"
if grep -E 'skills add https://github.com/[^ ]*modem-dev/hunk' scripts/install.sh >/dev/null; then
    fail "the Hunk review skill tracks GitHub head instead of the installed binary"
fi
grep -F 'agent_browser_version=0.33.2' scripts/install.sh >/dev/null \
    || fail "installer does not pin agent-browser to the Agentweb-locked build"
grep -F 'refusing to replace independent file' scripts/install.sh >/dev/null \
    || fail "installer would replace an independent ~/.local/bin/agent-browser"

# Pi reads its prompts from /dev/tty, so only removing the controlling
# terminal keeps the run unattended and stops it editing the Stow-managed
# shell profile.
grep -F 'run_without_controlling_terminal /bin/sh' scripts/install.sh >/dev/null \
    || fail "Pi installer is not detached from the controlling terminal"
grep -F 'POSIX::setsid()' scripts/install.sh >/dev/null \
    || fail "Pi installer detachment does not start a new session"

# The fleet statusline is one bar in three harness idioms: a render command
# for claude, a footer extension for pi, and an ordered pick from codex's
# fixed item set — codex has no custom renderer to install.
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-statusline" --install' scripts/install.sh >/dev/null \
    || fail "installer does not converge the fleet statusline"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-statusline" --check' scripts/install.sh >/dev/null \
    || fail "installation plan omits the fleet statusline"
[ -x scripts/install-statusline ] \
    || fail "the statusline installer is not executable"
for renderer in config/statusline/claude-statusline.sh config/statusline/pi-statusline.ts; do
    [ -s "$renderer" ] \
        || fail "statusline renderer is missing or empty: $renderer"
done
# Claude refuses an independent statusline; Pi's ambient slot is retired and
# an independent occupant is explicitly left untouched.
grep -F 'refusing to replace an independent claude renderer' scripts/install-statusline >/dev/null \
    || fail "the statusline installer would replace an independent Claude file"
grep -F 'Leaving independent pi extension untouched' scripts/install-statusline >/dev/null \
    || fail "the statusline installer would replace an independent Pi extension"
if grep -F 'agent-hooks/claude-statusline.sh' config/statusline/claude-statusline.sh >/dev/null; then
    fail "the claude renderer still forwards statusline payloads to the retired Orca sink"
fi
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-agentvoice-cli"' scripts/install.sh >/dev/null \
    || fail "installer does not install the AgentVoice voice CLI"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$agentvoice_cli_status"' scripts/install.sh >/dev/null \
    || fail "installer does not propagate an AgentVoice CLI installation failure"
# shellcheck disable=SC2016 # Match the literal helper invocation in the script.
grep -F '"$script_dir/install-agent-clis"' scripts/install.sh >/dev/null \
    || fail "installer does not install the agent CLIs"
# shellcheck disable=SC2016 # Match the literal status variable in the script.
grep -F 'exit "$agent_clis_status"' scripts/install.sh >/dev/null \
    || fail "installer does not propagate an agent CLI installation failure"
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
if grep -Eq 'rm -- .*herdr-agent-state|unlink .*herdr-agent-state' scripts/render-capabilities; then
    fail "render-capabilities removes Pi resources on the unattended path"
fi
grep -F 'remove_packed_pi_ambient_resources' scripts/install.sh >/dev/null \
    || fail "full installer does not retire Pi resources after packing them"
# The list spans two lines, so the order is checked on the joined text rather
# than by matching one literal line. agentusage must precede agentlaunch (the
# launcher shells its balance contract), agentweb must precede agentbrain
# (whose worker spawns the agentscrape children that ask agentweb's conduit),
# and codex-swap must precede agentusage so balance observes the command owner
# codex-swap itself installed.
agent_cli_order=$(tr '\n' ' ' <scripts/install-agent-clis | tr -s ' ')
case "$agent_cli_order" in
    *"for tool in agentwiki agentboard agentsearch agentkeys agentweb agentscrape \\ agentbrain codex-swap agentusage agentlaunch agentsurface"*) ;;
    *) fail "agent CLI installer changed its tool list or ordering" ;;
esac
# Every checkout with an installer is in the loop; a name missing from it is a
# tool nothing installs.
for expected_tool in agentwiki agentboard agentsearch agentkeys agentweb \
    agentscrape agentbrain codex-swap agentusage agentlaunch agentsurface; do
    case "$agent_cli_order" in
        *" $expected_tool "*) ;;
        *) fail "agent CLI loop no longer installs $expected_tool" ;;
    esac
done
case "$agent_cli_order" in
    *" agentbus "*) fail "agent CLI loop still installs retired agentbus" ;;
esac
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentchats_root="$code_root/agentchats"' scripts/install.sh >/dev/null \
    || fail "installer does not own the cass installation call"
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentdesk_root="$code_root/agentdesk"' scripts/install.sh >/dev/null \
    || fail "installer does not own the peekaboo installation call"
# One fleet root, honoured by every script that walks it. A script resolving
# $HOME/code directly cannot be pointed at a fixture tree, and one resolving it
# relative to its own location would silently skip the whole fleet on a worktree
# run — the checkouts are found where the machine keeps them, not beside $0.
for fleet_walker in scripts/install.sh scripts/install-agent-clis \
    scripts/install-agentvoice-cli scripts/remove-retired-integrations \
    scripts/sync-skills; do
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

# The ownership boundary, from this side: nothing here may install a desktop
# cask, migrate gh credentials, or grow launchd machinery — those are the
# machine's.
if grep -Eq -- '--cask' scripts/install.sh scripts/sync-skills; then
    fail "an AgentStart script crossed the boundary: casks are the machine's"
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
if rg -n 'agentbus\.(daemon|codex-appserver)' scripts/install-launchagents \
    config/launchd tests/validate.sh >/dev/null; then
    fail "retired AgentBus launch agents remain in the fleet service contract"
fi

expected_services='agentbrain.worker|agentbrain|worker.log|resident
agentbrain.share|agentbrain|share.log|resident
agentbrain.doctor|agentbrain|doctor.log|periodic
agentusage.observer|agentusage|observer.log|resident
agentweb.broker|agentweb|broker.log|resident
agentscrape.queue-processor|agentscrape|queue-processor.log|queue-triggered
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

printf 'ok\n'
