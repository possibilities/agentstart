#!/bin/bash

set -euo pipefail

root=$(cd -P -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/agentstart-agentsource-webhooks.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

fail() {
    printf 'agentsource-webhooks test: %s\n' "$*" >&2
    exit 1
}

home="$fixture/home"
fake_bin="$fixture/bin"
code_root="$fixture/code"
launch_agents="$home/Library/LaunchAgents"
install_bin="$home/.local/bin"
mkdir -p "$fake_bin" "$code_root" "$launch_agents" "$install_bin" \
    "$home/.config/agentsource"

printf '%064d\n' 0 >"$home/.config/agentsource/github-webhook-secret"
chmod 600 "$home/.config/agentsource/github-webhook-secret"
cat >"$launch_agents/agentsource.receiver.plist" <<'EOF'
<!-- agentstart-installer-owned: agentsource.receiver.v1 -->
EOF

cat >"$fake_bin/tailscale" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$1 $2" in
    'status --json')
        printf '{"BackendState":"Running","Self":{"DNSName":"testbird.example.ts.net."}}\n'
        ;;
    'funnel status')
        case "${FAKE_FUNNEL:-ready}" in
            ready)
                printf '{"TCP":{"443":{"HTTPS":true}},"Web":{"testbird.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8787"}}}},"AllowFunnel":{"testbird.example.ts.net:443":true}}\n'
                ;;
            conflict)
                printf '{"TCP":{"443":{"HTTPS":true}},"Web":{"testbird.example.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9999"}}}},"AllowFunnel":{"testbird.example.ts.net:443":true}}\n'
                ;;
            tcp-conflict)
                printf '{"TCP":{"443":{"TCPForward":"127.0.0.1:9999"}}}\n'
                ;;
            *) printf '{}\n' ;;
        esac
        ;;
    'funnel --bg')
        printf '%s\n' "$*" >>"$FAKE_CALLS"
        ;;
    *) exit 2 ;;
esac
EOF

cat >"$fake_bin/gh" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$1 $2 $3" = 'auth status --hostname' ]
[ "${FAKE_GH_AUTH:-ready}" = ready ]
EOF

cat >"$fake_bin/launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$1" = print ]
printf '    state = %s\n' "${FAKE_RECEIVER_STATE:-running}"
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
disable=0
noproxy=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --disable) disable=1 ;;
        --noproxy)
            shift
            [ "${1:-}" = '*' ] && noproxy=1
            ;;
    esac
    shift
done
[ "$disable" -eq 1 ] && [ "$noproxy" -eq 1 ]
printf '{"error":"method must be POST"}\n'
EOF

cat >"$install_bin/agentsource" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${FAKE_HOOKS:-ready}" = error ]; then
    printf 'repository hook listing failed\n' >&2
    exit 1
elif printf '%s\n' "$@" | grep -Fxq -- --apply; then
    printf 'github-apply %s\n' "$*" >>"$FAKE_CALLS"
    printf 'updated possibilities/example https://testbird.example.ts.net/possibilities/example\n'
elif [ "${FAKE_HOOKS:-ready}" = ready ]; then
    printf 'github-preflight %s\n' "$*" >>"$FAKE_CALLS"
    printf 'unchanged possibilities/example https://testbird.example.ts.net/possibilities/example\n'
else
    printf 'would-create possibilities/example https://testbird.example.ts.net/possibilities/example\n'
fi
EOF

chmod +x "$fake_bin/tailscale" "$fake_bin/gh" "$fake_bin/launchctl" "$fake_bin/curl" \
    "$install_bin/agentsource"
export HOME="$home"
export PATH="$fake_bin:$PATH"
export AGENTSTART_CODE_ROOT="$code_root"
export AGENTSTART_INSTALL_BIN_DIR="$install_bin"
export AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR="$launch_agents"
export AGENTSTART_INSTALL_LAUNCHCTL="$fake_bin/launchctl"
export FAKE_CALLS="$fixture/calls"
export http_proxy=http://hostile-proxy.invalid:9999

fingerprint=$(shasum -a 256 "$home/.config/agentsource/github-webhook-secret" | awk '{print $1}')
mkdir -p "$home/.local/state/agentstart"
printf '%s\n%s\n' https://testbird.example.ts.net "$fingerprint" \
    >"$home/.local/state/agentstart/agentsource-webhook-origin"
chmod 600 "$home/.local/state/agentstart/agentsource-webhook-origin"

healthy_output=$("$root/scripts/configure-agentsource-webhooks" --check 2>&1) \
    || fail "healthy check failed"
[ -z "$healthy_output" ] || fail "healthy check was not silent: $healthy_output"

export FAKE_RECEIVER_STATE=exited
if dead_output=$("$root/scripts/configure-agentsource-webhooks" --check 2>&1); then
    fail "dead receiver check unexpectedly succeeded"
fi
printf '%s\n' "$dead_output" | grep -F 'service or its loopback listener is not running' >/dev/null \
    || fail "diagnostic did not report a dead receiver"
unset FAKE_RECEIVER_STATE

export FAKE_FUNNEL=missing
if incomplete_output=$("$root/scripts/configure-agentsource-webhooks" --check 2>&1); then
    fail "incomplete check unexpectedly succeeded"
fi
for phrase in \
    'Agent handoff' \
    'Detected:' \
    'Operator approval required:' \
    'operator explicitly approves those external changes.' \
    'Agent action after that approval:' \
    'Human-only authorization' \
    'tailscale funnel --bg 8787' \
    'Never print, replace, copy, or pass the webhook secret value'; do
    printf '%s\n' "$incomplete_output" | grep -F "$phrase" >/dev/null \
        || fail "agent-oriented recovery omits: $phrase"
done

export FAKE_FUNNEL=ready
export FAKE_GH_AUTH=missing
: >"$FAKE_CALLS"
if auth_output=$("$root/scripts/configure-agentsource-webhooks" --apply 2>&1); then
    fail "apply proceeded without GitHub authentication"
fi
printf '%s\n' "$auth_output" | grep -F 'GitHub CLI needs human authentication' >/dev/null \
    || fail "missing GitHub authentication did not explain human recovery"
[ ! -s "$FAKE_CALLS" ] || fail "missing GitHub authentication mutated external state"
unset FAKE_GH_AUTH

export FAKE_HOOKS=error
: >"$FAKE_CALLS"
if preflight_output=$("$root/scripts/configure-agentsource-webhooks" --apply 2>&1); then
    fail "apply proceeded after GitHub preflight failed"
fi
printf '%s\n' "$preflight_output" | grep -F 'GitHub hook preflight failed' >/dev/null \
    || fail "GitHub preflight failure did not explain recovery"
[ ! -s "$FAKE_CALLS" ] || fail "GitHub preflight failure mutated Funnel state"
unset FAKE_HOOKS

: >"$FAKE_CALLS"
"$root/scripts/configure-agentsource-webhooks" --apply >/dev/null
grep -F 'funnel --bg 8787' "$FAKE_CALLS" >/dev/null \
    || fail "apply did not converge Funnel port 8787"
grep -F 'webhook-configure --url https://testbird.example.ts.net' "$FAKE_CALLS" >/dev/null \
    || fail "apply did not invoke the installed Agentsource webhook contract"
grep -F -- "--secret-file $home/.config/agentsource/github-webhook-secret" "$FAKE_CALLS" >/dev/null \
    || fail "apply did not pass the private secret by file path"
if grep -F "$(tr -d '\n' <"$home/.config/agentsource/github-webhook-secret")" "$FAKE_CALLS" >/dev/null; then
    fail "apply exposed the webhook secret value in command arguments"
fi
[ "$(sed -n '1p' "$FAKE_CALLS" | cut -d ' ' -f1)" = github-preflight ] \
    || fail "apply did not preflight GitHub before external mutation"
[ "$(sed -n '2p' "$FAKE_CALLS")" = 'funnel --bg 8787' ] \
    || fail "apply did not defer Funnel mutation until after GitHub preflight"
[ "$(sed -n '3p' "$FAKE_CALLS" | cut -d ' ' -f1)" = github-apply ] \
    || fail "apply did not reconcile GitHub after Funnel convergence"
[ "$(sed -n '1p' "$home/.local/state/agentstart/agentsource-webhook-origin")" = \
    https://testbird.example.ts.net ] || fail "apply did not record the converged Funnel origin"
[ "$(sed -n '2p' "$home/.local/state/agentstart/agentsource-webhook-origin")" = "$fingerprint" ] \
    || fail "apply did not bind its receipt to the stable secret"
[ "$(stat -f %Lp "$home/.local/state/agentstart/agentsource-webhook-origin")" = 600 ] \
    || fail "apply did not keep its origin receipt private"
if find "$home/.local/state/agentstart" -name '.agentsource-webhook-origin.*' -print -quit \
    | grep -q .; then
    fail "apply left a temporary origin receipt behind"
fi

export FAKE_FUNNEL=conflict
: >"$FAKE_CALLS"
if conflict_output=$("$root/scripts/configure-agentsource-webhooks" --apply 2>&1); then
    fail "apply replaced conflicting Funnel routing"
fi
printf '%s\n' "$conflict_output" | grep -F 'refusing to replace conflicting Funnel routing' \
    >/dev/null || fail "Funnel conflict refusal did not explain recovery"
[ ! -s "$FAKE_CALLS" ] || fail "Funnel conflict refusal mutated external state"

export FAKE_FUNNEL=tcp-conflict
: >"$FAKE_CALLS"
if tcp_conflict_output=$("$root/scripts/configure-agentsource-webhooks" --apply 2>&1); then
    fail "apply replaced conflicting TCP Funnel routing"
fi
printf '%s\n' "$tcp_conflict_output" | grep -F 'refusing to replace conflicting Funnel routing' \
    >/dev/null || fail "TCP Funnel conflict refusal did not explain recovery"
[ ! -s "$FAKE_CALLS" ] || fail "TCP Funnel conflict refusal mutated external state"

printf 'ok\n'
