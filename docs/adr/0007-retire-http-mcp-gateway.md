# 0007: Retire the HTTP MCP gateway

Accepted September 13, 2026. AgentStart no longer translates its fixed direct
MCP inventory into authenticated HTTP toolsets or publishes `/mcp` through
Tailscale Funnel. Managed Claude, Codex, and AgentVoice sessions continue to
receive the same stdio MCP inventory from
[`config/resources/mcp-servers.json`](../../config/resources/mcp-servers.json).

The FastMCP package, private toolset configuration, installer, command surface,
LaunchAgent template, and tests are removed together. `agentstart mcp shadcn`
remains because it is the stdio entrypoint for the fleet-owned shadcn registry;
`agentstart mcp serve` and `agentstart mcp check` retire with the HTTP transport.
AgentStart continues to own the direct inventory, not an external projection.

The source change deliberately carries no permanent retirement branch in the
installer. After deployment, Connect0r performs the bounded runtime teardown
below. It removes only the exact AgentStart-owned service and `/mcp` handler,
then removes the gateway's private state. The independently owned Funnel `/`
handler and all other Serve ports must remain byte-for-byte unchanged.

## Runtime teardown after deployment

Run from the deployed canonical AgentStart checkout. Do not substitute
`tailscale funnel reset` or `tailscale funnel --https=443 off`: either would
remove routes outside this retirement.

```bash
set -euo pipefail

mcp_label=io.arthack.agentstart.serve-mcp
mcp_target="gui/$(id -u)/$mcp_label"
mcp_plist="$HOME/Library/LaunchAgents/$mcp_label.plist"
mcp_config_root="$HOME/.config/agentstart"
mcp_checkout="$(git rev-parse --show-toplevel)"

test "$mcp_checkout" = "$HOME/code/agentstart"
grep -Fqx '<!-- agentstart-installer-owned: io.arthack.agentstart.serve-mcp.v1 -->' "$mcp_plist"
jq -e --arg home "$HOME" \
  '.owner == "agentstart-mcp-gateway.v1" and .config == ($home + "/.config/agentstart/mcp-gateway.json")' \
  "$mcp_config_root/mcp-gateway-install.json"
jq -e '.port == 4790 and (.toolsets | keys) == ["fleet", "grok"]' \
  "$mcp_config_root/mcp-gateway.json"

mcp_funnel_host="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".") + ":443"')"
mcp_funnel_before="$(tailscale funnel status --json)"
jq -e --arg host "$mcp_funnel_host" '
  .AllowFunnel[$host] == true and
  .Web[$host].Handlers["/"].Proxy == "http://127.0.0.1:8787" and
  .Web[$host].Handlers["/mcp"].Proxy == "http://127.0.0.1:4790/mcp"
' <<<"$mcp_funnel_before"

tailscale funnel --yes --https=443 --set-path=/mcp off

mcp_funnel_after="$(tailscale funnel status --json)"
mcp_funnel_expected="$(jq --arg host "$mcp_funnel_host" \
  'del(.Web[$host].Handlers["/mcp"])' <<<"$mcp_funnel_before")"
test "$(jq -S . <<<"$mcp_funnel_after")" = "$(jq -S . <<<"$mcp_funnel_expected")"

launchctl bootout "$mcp_target"
for mcp_wait in {1..30}; do
  if ! launchctl print "$mcp_target" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
! launchctl print "$mcp_target" >/dev/null 2>&1

rm -f -- \
  "$mcp_plist" \
  "$mcp_config_root/mcp-gateway.json" \
  "$mcp_config_root/mcp-gateway-install.json" \
  "$mcp_config_root/mcp-credentials/fleet.json" \
  "$mcp_config_root/mcp-credentials/grok.json" \
  "$mcp_config_root/mcp-clients/fleet.json" \
  "$mcp_config_root/mcp-clients/grok.json" \
  "$HOME/.local/state/agentstart/mcp-gateway.log"
rmdir -- "$mcp_config_root/mcp-credentials" "$mcp_config_root/mcp-clients"

mcp_venv="$mcp_checkout/gateway/.venv"
if test -e "$mcp_venv"; then
  test -d "$mcp_venv"
  test ! -L "$mcp_venv"
  rm -rf -- "$mcp_venv"
fi
rmdir -- "$mcp_checkout/gateway"

! lsof -nP -iTCP:4790 -sTCP:LISTEN
tailscale funnel status --json
tailscale serve status --json
scripts/configure-agentsource-webhooks --check
```

The retained `/` handler is a prefix route, so public requests under `/mcp`
may subsequently reach the webhook backend as ordinary unmatched paths. The
postcondition is that Funnel has no dedicated `/mcp` handler and no process
listens on port 4790, not that the public path cannot receive an HTTP response.
