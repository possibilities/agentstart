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
scripts/install-gog
scripts/sync-skills
scripts/run-skills-cli
scripts/render-capabilities
scripts/sync-codex-skill-policy
scripts/install-agent-clis
scripts/install-agentvoice-android
scripts/install-agentlaunch-shims
scripts/install-notification-shim
scripts/install-launchagents
scripts/configure-agentsource-webhooks
scripts/agentbrowse-config
scripts/agent-browser-config
scripts/agent-browser-link.sh
scripts/smolmux-config
scripts/agentmux-config
scripts/agentvoice-config
scripts/herdr-config
scripts/herdr-socket-state
tests/validate.sh
tests/agentbrowse-config.sh
tests/agent-browser-config.sh
tests/agent-browser-link.sh
tests/smolmux-config.sh
tests/agentmux-config.sh
tests/agentvoice-config.sh
tests/herdr-config.sh
tests/herdr-socket-state.sh
tests/agentsource-webhooks.sh
tests/install-launchagents.sh
tests/fixtures/npx
"

for file in $shell_files; do
    /bin/bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    shellcheck --shell=bash $shell_files
fi

for script in scripts/install.sh scripts/sync-skills scripts/install-agent-clis scripts/install-agentvoice-android \
    scripts/run-skills-cli \
    scripts/install-agentlaunch-shims scripts/render-capabilities scripts/install-launchagents \
    scripts/configure-agentsource-webhooks \
    scripts/sync-codex-skill-policy \
    scripts/render-skill-invocation-policy \
    scripts/agentbrowse-config scripts/agent-browser-config scripts/smolmux-config scripts/agentmux-config scripts/agentvoice-config scripts/herdr-config \
    scripts/herdr-socket-state; do
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
[ -x tests/herdr-socket-state.sh ] \
    || fail "Herdr socket-state test is not executable: tests/herdr-socket-state.sh"
[ -x tests/agentsource-webhooks.sh ] \
    || fail "Agentsource webhook test is not executable: tests/agentsource-webhooks.sh"
[ -x tests/install-launchagents.sh ] \
    || fail "launch agent installer test is not executable: tests/install-launchagents.sh"
[ -x config/terminal-control/termctrl ] \
    || fail "Terminal Control shim is missing or not executable"
/usr/bin/python3 -c \
    'import pathlib; compile(pathlib.Path("config/terminal-control/termctrl").read_text(), "config/terminal-control/termctrl", "exec")'
PYTHONDONTWRITEBYTECODE=1 python3 tests/render-terminal-control-skill.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/render-agentvoice-role.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/project-docs.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/check-project-docs.py "$root"

[ -s config/agentbrowse/config.json ] \
    || fail "default agentbrowse config is missing or empty"
/usr/bin/jq -e '
    .version == 2 and
    (.backends | map(.id)) == ["artbird", "local"] and
    (.backends | all(.type == "hypeman" and .cpus == 2 and .memory == "3G")) and
    .backends[0].video == {"fps": 60, "targetBitrateBps": 4792320, "keyframeMaxDistance": 60} and
    (.backends[1] | has("video") | not) and
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
uv sync --frozen --project gateway
PYTHONDONTWRITEBYTECODE=1 python3 tests/mcp-install.py
PYTHONDONTWRITEBYTECODE=1 gateway/.venv/bin/python -m unittest discover -s gateway -p 'test_*.py'
for script in render-mcp-resources install-gog install-mcp-gateway; do
    [ -x "scripts/$script" ] || fail "MCP delivery helper is not executable: $script"
done
scripts/render-mcp-resources --check config/resources/mcp-servers.json
python3 - <<'PYTHON'
from pathlib import Path
source = Path("scripts/install.sh").read_text()
content = source.rindex("\nconverge_repo_content\n")
prepare = source.index('"$script_dir/install-mcp-gateway" --install')
services = source.index('"$script_dir/install-launchagents" --install')
expose = source.index('"$script_dir/install-mcp-gateway" --expose')
assert content < prepare < services < expose
for name in ["sync-skills", "render-capabilities"]:
    body = Path("scripts", name).read_text()
    assert "install-mcp-gateway" not in body
PYTHON

for manifest in config/resources/*.json; do
    /usr/bin/jq -e . "$manifest" >/dev/null \
        || fail "resource manifest is not valid JSON: $manifest"
done
/usr/bin/jq -e '.name == "agent"' config/resources/claude-plugin.json >/dev/null \
    || fail "Claude fleet plugin has the wrong name"
python3 - <<'PYTHON'
import json
from pathlib import Path
servers=json.loads(Path("config/resources/mcp-servers.json").read_text())["mcpServers"]
fleet=["agentattention","agentboard","agentbrain","agentbrowse","agentchats",
       "agentdesk","agentgrok","agentkeys","agentnotify","agentscrape","agentsearch","agentsounds","agentsurface","agentwiki","termctrl"]
assert set(servers) == set(fleet+["agent_browser","gog_mikebannister","gog_notimpossiblemike","shadcn"])
for name in fleet:
    assert servers[name] == {"command":"${HOME}/.local/bin/"+name,"args":["mcp"]}
assert servers["agent_browser"] == {"command":"${HOME}/.local/bin/agent-browser","args":["mcp","--tools","all"]}
for name in ["mikebannister","notimpossiblemike"]:
    assert servers["gog_"+name] == {"command":"gog","args":["--account",name+"@gmail.com","mcp","--allow-write"]}
assert servers["shadcn"] == {"command":"${HOME}/.local/bin/agentstart","args":["mcp","shadcn"]}
components=json.loads(Path("config/resources/shadcn/components.json").read_text())
assert components["$schema"] == "https://ui.shadcn.com/schema.json"
assert components["registries"] == {}
assert json.loads(Path("config/resources/shadcn/package.json").read_text()) == {
    "name":"agentstart-shadcn-registry", "private":True,
}
PYTHON
/usr/bin/jq -e '.name == "agent" and .skills == "./skills/" and .interface.capabilities == ["Skills"]' \
    config/resources/codex-plugin.json >/dev/null \
    || fail "Codex fleet plugin is not strictly skills-only"
if grep -Ei '"(hooks|mcpServers|apps)"[[:space:]]*:' config/resources/codex-plugin.json >/dev/null; then
    fail "Codex fleet plugin declares a globally active non-skill surface"
fi
# The installer links these into ~/.config/agentguidance and agentguidance
# renders every skill against them, so an empty or missing prompt ships
# broken skills to a fresh account.
for prompt in SYSTEM.md GUIDELINES.md; do
    [ -s "prompts/agentguidance/$prompt" ] \
        || fail "extension prompt is missing or empty: prompts/agentguidance/$prompt"
done
# Persistent guidance is file-backed rather than delegated to harness memory,
# and fleet-specific personal guidance stays in AgentStart's extension layer.
grep -F 'Do not use harness-provided agent memory' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not reject harness-provided agent memory"
grep -F 'Place global personal guidance tied to the' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not keep fleet-specific personal guidance in AgentStart"
grep -F 'https://vercel.com/design.md' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not require Vercel design guidance as the design baseline"
grep -F 'documentation and guidelines in the wiki' prompts/agentguidance/GUIDELINES.md >/dev/null \
    || fail "GUIDELINES.md does not route design work through the wiki"
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
# only one of them. --content runs it alone; full installation publishes it
# before starting the HTTP gateway that consumes the same inventory.
grep -q '^converge_repo_content() {$' scripts/install.sh \
    || fail "install.sh does not define converge_repo_content"
[ "$(grep -c '^converge_repo_content$' scripts/install.sh)" -eq 1 ] \
    || fail "converge_repo_content must have exactly one call site in the full install"
grep -q -- '--content)' scripts/install.sh \
    || fail "install.sh does not accept --content"
for content_step in link_extension_prompts link_agent_guidance; do
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
PYTHONDONTWRITEBYTECODE=1 python3 tests/notification-shim.py
bun test tests/install-agentvoice-android.test.ts
bun test tests/agentvoice-network.test.ts

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
# and therefore never belongs in a path or machine-specific value. The
# account-wide `io.arthack.*` launch service namespace is an explicit naming
# contract, not a runtime account assumption.
operator_account=$(id -un)
# shellcheck disable=SC2086 # $hygiene_paths is a deliberate list of targets.
if grep -rn "$operator_account" $hygiene_paths 2>/dev/null \
    | grep -vF 'io.arthack.' \
    | grep -vF 'io\.arthack\.'; then
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
[ -x "$root/scripts/codex-invocation" ] || fail "Codex invocation helper is not executable"
bun test "$root/tests/codex-invocation.test.ts" "$root/tests/harness-config.test.ts"
"$root/scripts/validate-agent-contract.ts" "$root/scripts/agentstart"
[ -x "$root/scripts/claude-invocation" ] || fail "Claude invocation helper is not executable"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/tests/claude-invocation.py"
# shellcheck disable=SC2016 # Match the installer source, not this environment.
grep -F '"$script_dir/install-agentlaunch-shims"' scripts/install.sh >/dev/null \
    || fail "full installer does not converge invocation-aware harness shims"
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
    "$code_skills_root/notagent/skills/x"
for code_skills_fixture in \
    agentbus/skills/bus \
    agentdemo/skills/demo \
    agentdemo/skills/second \
    agentexample/skills/example \
    notagent/skills/x; do
    code_skills_name=${code_skills_fixture##*/}
    printf -- '---\nname: %s\ndescription: fixture skill\n---\n' "$code_skills_name" \
        >"$code_skills_root/$code_skills_fixture/SKILL.md"
done
# A vendor skill may enumerate provider origins outside the managed fleet.
# The fixed-resource renderer preserves the variable contract but narrows its
# documented values before copying resources into either managed plugin.
cat >>"$code_skills_root/agentdemo/skills/demo/SKILL.md" <<'EOF'

| Variable | Description |
| --- | --- |
| `PLANNOTATOR_ORIGIN` | unsupported-origin fixture |
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
name = "agent:stale"
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
if grep -F 'unsupported-origin fixture' "$fixture_resources_root/skills/demo/SKILL.md" >/dev/null; then
    fail "fixed-resource rendering retained unsupported vendor-origin guidance"
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
cmp -s config/resources/shadcn/components.json "$fixture_resources_root/shadcn/components.json" \
    || fail "skill sync did not render the fleet shadcn registry config"
cmp -s config/resources/shadcn/package.json "$fixture_resources_root/shadcn/package.json" \
    || fail "skill sync did not render the fleet shadcn package boundary"
HOME="$code_skills_home" scripts/render-mcp-resources config/resources/mcp-servers.json "$skip_test_dir/expected-mcp.json"
cmp -s "$skip_test_dir/expected-mcp.json" "$fixture_resources_root/mcp-servers.json" \
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

# A plugin refresh can fail after persistent policy is written. Keep a stale
# name disabled until a later successful refresh proves the old plugin content
# is gone; pruning it first would make that stale installed skill ambient.
fixture_codex_config_next="$fixture_codex_config.next"
/usr/bin/awk '
    $0 == "# END AgentStart managed fleet skills" {
        print "[[skills.config]]"
        print "name = \"agent:stale\""
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
grep -F 'name = "agent:stale"' "$fixture_codex_config" >/dev/null \
    || fail "failed Codex plugin refresh pruned a stale skill disable"
HOME="$code_skills_home" CODEX_HOME="$code_skills_home/.codex" \
    AGENTSTART_RESOURCES_ROOT="$fixture_resources_root" \
    AGENTSTART_CODEX_BIN=/usr/bin/true \
    "$root/scripts/render-capabilities" --install >/dev/null
if grep -F 'name = "agent:stale"' "$fixture_codex_config" >/dev/null; then
    fail "successful Codex plugin refresh did not prune a stale skill disable"
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
# The installation plan embeds the skill sync's own plan, pointed at the
# fixture tree so the asserted lines are the same on every machine.
install_plan=$(HOME="$code_skills_home" AGENTSTART_CODE_ROOT="$code_skills_root" "$root/scripts/install.sh" --check)

# The full installer owns the current CLI-only cask.
grep -F 'install_or_upgrade_cask grok-build' scripts/install.sh >/dev/null \
    || fail "the full installer does not converge the Grok Build cask"
# shellcheck disable=SC2016,SC2088 # Plan lines are literal, including $ and ~.
for required_install in \
    '~/code/agentvoice/scripts/install.sh --install  # via install-agent-clis: editable command + native audio build + waiting default LaunchAgent; no voice call' \
    '~/code/agentnotify/scripts/install.sh --install  # native menu bar inbox + parity CLI; preserve the current running release' \
    'install ~/.local/bin/terminal-notifier router  # prefer AgentNotify; keep the real notifier as an availability fallback' \
    'brew install or upgrade --cask grok-build  # official Grok Build CLI/TUI; no AgentLaunch or Herdr integration' \
    'curl -fsSL https://claude.ai/install.sh | XDG_CACHE_HOME=~/Library/Caches bash  # keep vendor staging off a machine-managed ~/.cache symlink' \
    'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh' \
    'curl -fsSL https://plannotator.ai/install.sh | bash -s -- --version v0.27.9 --minimal --non-interactive  # binary only; AgentStart carries the skills' \
    '~/.local/bin/plannotator install-runtime agent-terminal  # managed WebTUI/PTY runtime omitted by the minimal installer' \
    'brew install or upgrade zig  # Native SDK packaging requires it' \
    '~/code/fxnk/scripts/install.sh --install --sha e6ef2148c63f304883de21768bcfcdbf97c4d833  # exact ship-gate-approved Fx Integration consumer pin' \
    'brew install or upgrade llm  # an AI CLI, so AgentStart'"'"'s outright — moved out of the machine'"'"'s Brewfile' \
    'brew install or upgrade hunk  # review-first diff TUI whose bundled agent skill follows the installed build' \
    'brew install or upgrade rustup  # Terminal Control builds from crates.io with the current stable Rust toolchain' \
    'brew install or upgrade zig@0.15  # Terminal Control'"'"'s libghostty-vt build requires the keg-only 0.15 line' \
    '"$(brew --prefix rustup)/bin/rustup" toolchain install stable --profile minimal' \
    'PATH="$(brew --prefix)/opt/zig@0.15/bin:$PATH" "$(brew --prefix rustup)/bin/rustup" run stable cargo install --locked --root "$HOME/.local" terminal-control' \
    'install AgentStart'"'"'s detached-start shim at ~/.local/bin/termctrl while retaining the upstream executable under ~/.local/libexec/agentstart/terminal-control' \
    'brew install herdr when absent and every default/named server socket is proved inactive; upgrade only with AGENTSTART_HERDR_ALLOW_UPGRADE=1 and the same socket gate' \
    'herdr integration install claude and codex into their canonical homes' \
    '~/code/smolmux/scripts/install.sh --install  # canonical consumer path: editable smolmux plus its exact source-built smolmux-zmx Companion pin' \
    'scripts/smolmux-config install  # link the Herdr-compatible smolmux key subset with the operator'"'"'s Ctrl-Space prefix' \
    'scripts/herdr-config install  # render, validate, and activate the generated Herdr config, then reload it' \
    'npm install --global @native-sdk/cli@0.7  # the line the native-sdk skill documents' \
    'npm install --global agent-browser@0.33.2  # Agentbrowse provider + Agentscrape stable-session driver share this exact build' \
    'ln -sfn "$(realpath "$(npm prefix --global)/bin/agent-browser")" ~/.local/bin/agent-browser  # the candidate Agentscrape resolves before PATH' \
    'scripts/agentbrowse-config install  # link the locked Artbird-first, already-enabled-Apple-second deployment configuration' \
    'scripts/agent-browser-config install  # select agentbrowse'"'"'s short-lived ordered provider; no provider server or static URL' \
    'native skills list' \
    'ln -sfn ~/.local/share/agentstart/resources/guidance/AGENTS.md ~/.claude/CLAUDE.md  # Claude Code reads CLAUDE.md, not AGENTS.md' \
    'ln -sfn ~/.local/share/agentstart/resources/guidance/AGENTS.md ~/.codex/AGENTS.md  # Codex skips empty guidance files' \
    'ln -sfn prompts/agentguidance/{SYSTEM,GUIDELINES}.md into ~/.config/agentguidance  # the extension prompts agentguidance renders against' \
    'install external skill packs with --copy into ~/.local/share/agentstart/resources/skills' \
    'scripts/install-gog --install  # direct Google MCP access; existing account credentials stay in gogcli' \
    'scripts/install-mcp-gateway --install  # private toolsets and per-toolset credentials; pinned FastMCP transport' \
    'scripts/install-mcp-gateway --expose  # authenticated /mcp/<toolset> through Tailscale, preserving unrelated routes' \
    'render the individual fleet MCPs, termctrl, agent-browser, gog, and fleet shadcn registry service for managed sessions and HTTP toolsets' \
    'https://github.com/vercel-labs/skills: find-skills' \
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
    'narrow vendor provider-origin guidance to retained Claude/Codex values' \
    'render one session-only Claude plugin named agent (/agent:<skill>) with the fleet MCP inventory' \
    'render and refresh the skills-only Codex plugin agent@agentstart-managed' \
    'persistently disable every agent:<skill> outside managed Codex sessions' \
    'leave binary installation and service restarts to the explicit full installer' \
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
# shellcheck disable=SC2016 # Match the literal per-user cache root.
grep -F 'XDG_CACHE_HOME="$HOME/Library/Caches" install_official "Claude Code"' \
    scripts/install.sh >/dev/null \
    || fail "Claude's native installer does not use the stable macOS cache root"
# Official installers run only after curl has completed. A vendor script may
# stop reading stdin early, and a curl-to-interpreter pipe would then fail the
# otherwise successful install under pipefail with curl error 56.
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F 'installer_file=$(mktemp "${TMPDIR:-/tmp}/agentstart-official-installer.XXXXXX")' \
    scripts/install.sh >/dev/null \
    || fail "official installers do not download into a private temporary file"
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F '/usr/bin/curl -fsSL "$url" -o "$installer_file"' scripts/install.sh >/dev/null \
    || fail "official installers are not downloaded completely before execution"
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F 'trap '\''rm -f -- "$installer_file"'\'' EXIT' scripts/install.sh >/dev/null \
    || fail "official installer temporary files are not cleaned up on exit"
# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F '"$interpreter" "$@" <"$installer_file"' scripts/install.sh >/dev/null \
    || fail "official installers are not executed from their completed downloads"

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
# shellcheck disable=SC2016 # Assert the literal environment pin in the installer.
grep -F 'CLAUDE_CONFIG_DIR="$HOME/.claude" "$herdr_bin" integration install "$harness"' \
    scripts/install.sh >/dev/null \
    || fail "Herdr's Claude integration can inherit a claude-swap session CLAUDE_CONFIG_DIR"
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
# belong to the machine layer. Grok Build is the sole CLI-only cask exception.
if printf '%s\n' "$install_plan" | grep -F -- '--cask' \
    | grep -Fv \
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
grep -F 'link_extension_prompts' scripts/install.sh >/dev/null \
    || fail "installer does not link the operator extension prompts"
grep -F 'refusing to replace independent extension prompt' scripts/install.sh >/dev/null \
    || fail "installer would replace an independent extension prompt"
for prompt_name in SYSTEM.md GUIDELINES.md; do
    grep -F "$prompt_name" scripts/install.sh >/dev/null \
        || fail "installer does not link the $prompt_name extension prompt"
done
# shellcheck disable=SC2016 # Match the literal rendered guidance source path.
grep -F 'source="$resources_root/guidance/AGENTS.md"' scripts/install.sh >/dev/null \
    || fail "installer does not own the harness guidance source"
grep -F 'install_or_upgrade_formula llm' scripts/install.sh >/dev/null \
    || fail "installer does not converge the llm CLI"

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

# Herdr uses the official stable formula. A fresh install and every upgrade
# must prove all default/named sockets inactive; upgrades also require an
# explicit maintenance flag. The selected client must meet protocol 20.
grep -F 'install_or_upgrade_formula zig@0.15' scripts/install.sh >/dev/null \
    || fail "installer does not converge the Zig 0.15 line Terminal Control builds against"
grep -F 'install_or_upgrade_formula herdr' scripts/install.sh >/dev/null \
    || fail "installer does not converge the official stable Herdr formula"
# shellcheck disable=SC2016
grep -F 'herdr_socket_state=$("$script_dir/herdr-socket-state")' scripts/install.sh >/dev/null \
    || fail "installer does not inspect Herdr sockets before Homebrew convergence"
grep -F 'AGENTSTART_HERDR_ALLOW_UPGRADE must be 0 or 1' scripts/install.sh >/dev/null \
    || fail "Herdr upgrades do not require explicit maintenance authorization"
grep -F 'Deferring Homebrew Herdr installation or upgrade while a server socket is present.' scripts/install.sh >/dev/null \
    || fail "installer does not preserve installed Herdr bytes around a live server"
# shellcheck disable=SC2016 # Match the literal protocol variable.
grep -F '[ "$herdr_protocol" -ge 20 ]' scripts/install.sh >/dev/null \
    || fail "installer does not enforce the fleet Herdr protocol floor"
# shellcheck disable=SC2016 # Match the literal config-root variable.
grep -F '[ ! -L "$root" ]' scripts/herdr-socket-state >/dev/null \
    || fail "Herdr socket inspection follows an uncertain config-root symlink"
[ ! -e scripts/update-herdr ] \
    || fail "a second Herdr update path returned"
if grep -F 'herdr.dev/install.sh' scripts/install.sh >/dev/null; then
    fail "installer uses Herdr's direct installer instead of Homebrew"
fi
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
# Smolmux owns its editable command, exact Companion pin, and doctor verification
# in its canonical source installer. AgentStart supplies the shared binary
# destination.
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
tests/agentvoice-config.sh
# shellcheck disable=SC2016 # Match the literal installer variable.
grep -F '"$script_dir/agentvoice-config" install' scripts/install.sh >/dev/null \
    || fail "AgentVoice configuration is not wired into installation"

# shellcheck disable=SC2016 # Match the literal installer variables.
grep -F 'AGENTSTART_HERDR_BIN="$herdr_bin" "$script_dir/herdr-config" install' scripts/install.sh >/dev/null \
    || fail "installer does not render the Herdr config"
tests/herdr-config.sh
tests/herdr-socket-state.sh

# The AgentSurface popup-pane and tab-naming plugin registers by checkout path;
# linking every run is the converge, and a missing agentsurface checkout is a
# skip, not a failure.
grep -F 'install_herdr_plugins' scripts/install.sh >/dev/null \
    || fail "installer does not link the agentsurface herdr plugin"
# shellcheck disable=SC2016 # Match the literal link invocation, $-sign and all.
grep -F '"$herdr_bin" plugin link "$plugin_root"' scripts/install.sh >/dev/null \
    || fail "the agentsurface plugin is not registered by checkout path"
# shellcheck disable=SC2016 # Match the literal captured-output variable.
if grep -F 'printf '\''%s\\n'\'' "$link_output"' scripts/install.sh >/dev/null; then
    fail "plugin convergence replays Herdr's successful JSON payload"
fi
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

if grep -Eq 'plugin (uninstall|remove)|plugin marketplace remove' scripts/render-capabilities; then
    fail "render-capabilities uninstalls plugins on the unattended path"
fi
# shellcheck disable=SC2016 # Match literal generated-manifest variables.
grep -F 'mv -f -- "$manifest.next" "$manifest"' scripts/render-capabilities >/dev/null \
    || fail "render-capabilities may prompt before replacing an immutable generated manifest"
# The list spans two lines, so the order is checked on the joined text rather
# than by matching one literal line. agentusage must precede agentlaunch (the
# launcher shells prepare). AgentUsage owns all three account inventories.
agent_cli_order=$(tr '\n' ' ' <scripts/install-agent-clis | tr -s ' ')
case "$agent_cli_order" in
    *"for tool in agentwiki agentboard agentbrowse agentattention agentutils agentsearch agentkeys agentsource agentscrape \\ agentbrain agentusage agentlaunch agentsurface"*) ;;
    *) fail "agent CLI installer changed its tool list or ordering" ;;
esac
# Every checkout with an installer is in the loop; a name missing from it is a
# tool nothing installs.
for expected_tool in agentwiki agentboard agentbrowse agentattention agentutils agentsearch agentkeys agentsource \
    agentscrape agentbrain agentusage agentlaunch agentsurface agentsounds agentgrok agentvoice agentnotify; do
    case "$agent_cli_order" in
        *" $expected_tool "*) ;;
        *) fail "agent CLI loop no longer installs $expected_tool" ;;
    esac
done
case "$agent_cli_order" in
    *" grok-swap "*) fail "agent CLI loop still installs the retired Grok account owner" ;;
esac
account_bar=$(printf '{}\n' | AGENTUSAGE_ACCOUNT=claude-7 CLAUDE_CONFIG_DIR=/shared/native config/statusline/claude-statusline.sh)
printf '%s' "$account_bar" | grep -F 'claude-7' >/dev/null || fail "Claude statusline lost managed identity"

# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentchats_root="$code_root/agentchats"' scripts/install.sh >/dev/null \
    || fail "installer does not own the agentchats installation call"
# shellcheck disable=SC2016 # Match the literal checkout resolution in the script.
grep -F 'agentdesk_root="$code_root/agentdesk"' scripts/install.sh >/dev/null \
    || fail "installer does not own the Agentdesk installation call"
# One fleet root, honoured by every script that walks it. A script resolving
# $HOME/code directly cannot be pointed at a fixture tree, and one resolving it
# relative to its own location would silently skip the whole fleet on a worktree
# run — the checkouts are found where the machine keeps them, not beside $0.
for fleet_walker in scripts/install.sh scripts/install-agent-clis scripts/sync-skills; do
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
    || fail "installer does not invoke the Agentdesk installation contract"

# Grok Build is the only CLI-only cask installed by AgentStart.
if grep -Eq -- '--cask' scripts/sync-skills; then
    fail "the unattended sync tried to install a Homebrew cask"
fi
# shellcheck disable=SC2016
if grep -E -- '--cask' scripts/install.sh | grep -Ev 'grok-build|"\$cask"' >/dev/null; then
    fail "an AgentStart script installs an unowned Homebrew cask"
fi
if [ "$(grep -Ec '^install_or_upgrade_cask ' scripts/install.sh)" -ne 1 ] \
    || ! grep -Fx 'install_or_upgrade_cask grok-build' scripts/install.sh >/dev/null; then
    fail "the installer does not own exactly the Grok Build cask"
fi
if grep -F 'oauth_token' scripts/install.sh >/dev/null; then
    fail "an AgentStart script crossed the boundary: gh migration is the machine's"
fi
# launchd is split by exact installer ownership, not by namespace. Every fleet
# service still uses the account-wide launch service label grammar.
for template in config/launchd/*.plist; do
    grep -Eq '<string>io\.arthack\.[a-z0-9-]+\.[a-z0-9-]+</string>' "$template" \
        || fail "an AgentStart launch agent does not use io.arthack.<project>.<verb>: $template"
done
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
expected_services='io.arthack.agentstart.watch-config|agentstart|config-watch.log|resident
io.arthack.agentbrain.work|agentbrain|worker.log|resident
io.arthack.agentbrain.share|agentbrain|share.log|resident
io.arthack.agentbrain.doctor|agentbrain|doctor.log|periodic
io.arthack.agentusage.observe|agentusage|observer.log|resident
io.arthack.agentattention.serve|agentattention|server.log|resident
io.arthack.agentscrape.process-queue|agentscrape|queue-processor.log|queue-triggered
io.arthack.agentsource.receive|agentsource|receiver.log|resident
io.arthack.agentsource.notify|agentsource|notifier.log|resident
io.arthack.agentwiki.serve|agentwiki|server.log|resident'
for entry in $expected_services; do
    grep -Fq "\"$entry\"" scripts/install-launchagents \
        || fail "launch agent manifest omits canonical entry: $entry"
done
for template in config/launchd/*.plist; do
    label=$(basename "$template" .plist)
    # The marker is what lets the installer tell its own service from a
    # stranger's, so a template whose marker does not match its own file name
    # would be refused forever.
    grep -Fq "agentstart-installer-owned: $label.v1" "$template" \
        || fail "template is missing or misnaming its ownership marker: $template"
    grep -Fq "<string>$label</string>" "$template" \
        || fail "template Label does not match its file name: $template"
    # Every value is rendered from the manifest through the standard tokens.
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
done < <(sed -n 's/^ *"\(io\.arthack\.[a-z-]*\.[a-z-]*\)|.*/\1/p' scripts/install-launchagents)

grep -Fq '<string>webhook-daemon</string>' config/launchd/io.arthack.agentsource.receive.plist \
    || fail "Agentsource receiver does not enter through the installed webhook-daemon subcommand"
grep -Fq '<string>notify-daemon</string>' config/launchd/io.arthack.agentsource.notify.plist \
    || fail "Agentsource notifier does not enter through the installed notify-daemon subcommand"
# The notifier uses the managed terminal-notifier router before Homebrew;
# the standard service PATH keeps both the primary and fallback reachable.
grep -Fq '<string>__PATH__</string>' config/launchd/io.arthack.agentsource.notify.plist \
    || fail "Agentsource notifier does not take the standard PATH that reaches terminal-notifier"
grep -Fq '<string>serve</string>' config/launchd/io.arthack.agentattention.serve.plist \
    || fail "Agentattention server does not enter through the installed serve subcommand"
if grep -Eq '<key>[^<]*(TOKEN|SECRET)[^<]*</key>' config/launchd/io.arthack.agentattention.serve.plist; then
    fail "Agentattention server rendered a credential-shaped environment variable"
fi
grep -Fq '<string>__SECRET_FILE__</string>' config/launchd/io.arthack.agentsource.receive.plist \
    || fail "Agentsource receiver does not name the private secret by path"
grep -A1 -F '<string>--port</string>' config/launchd/io.arthack.agentsource.receive.plist \
    | grep -Fq '<string>8787</string>' \
    || fail "Agentsource receiver does not pin its Funnel-coupled HTTP port"
if grep -Eq '<key>[^<]*SECRET[^<]*</key>' config/launchd/io.arthack.agentsource.receive.plist; then
    fail "Agentsource receiver rendered a credential-shaped environment variable"
fi

printf 'ok\n'
