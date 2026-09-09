# Authenticated MCP toolsets

AgentStart runs pinned FastMCP on 127.0.0.1:4790 and exposes it through the
node's existing Tailscale Funnel. The shared direct MCP inventory is the only
source of stdio commands. The gateway selects tools from it without adding an
execution language or another tool catalog.

## Configure

The full installer seeds ~/.config/agentstart/mcp-gateway.json from
config/mcp-gateway.json. Subsequent installs preserve operator edits. The
default fleet set includes all declared fleet tools and both bound Gog
mailboxes. The default grok set includes AgentBoard, AgentBrain, AgentChats,
AgentNotify, AgentSearch, AgentWiki, Terminal Control, shadcn, and both bound Gog mailboxes.
The fleet set also exposes shadcn, backed by AgentStart's fixed registry
configuration rather than the caller's project files.

AgentNotify adoption adds its complete MCP to existing `fleet` and `grok`
toolsets once, recorded as `agentnotify-fleet-grok.v1` in the owned installation
receipt. Existing explicit AgentNotify restrictions, custom toolsets, and
credentials are preserved; later operator changes are not overwritten.
Its wildcard includes new preference operations along with durable inbox tools.

Each toolsets entry has a tools map from inventory server name to native tool
names. A single "*" selects every tool on that server. An explicit list limits
both discovery and calls; native resources and prompts are not exposed.
For example, add this entry alongside fleet:

    "reading": {
      "tools": {
        "agentbrain": ["guide", "search"],
        "gog_mikebannister": ["gmail_search", "gmail_get_message"]
      }
    }

Use the server's live tools/list for exact native names. HTTP names are
namespaced as SERVER_TOOL. The reading endpoint is /mcp/reading. There is no
implicit /mcp or catch-all toolset.

Run scripts/install-mcp-gateway --install to validate and provision changes,
then restart the owned gateway service through scripts/install-launchagents
--install. The full scripts/install.sh --install performs both in order and
converges the Funnel route. Ordinary content/skill sync does not restart it.

The installer creates a separate credential for each set and fills its
credential path. Server files in ~/.config/agentstart/mcp-credentials contain
only SHA-256 digests. Private client settings in ~/.config/agentstart/mcp-clients
contain each URL and bearer token. Files are owner-only; never put their
contents in commands, logs, repositories, messages, or launchd plists. Existing
credentials remain stable across installs. A token for one set cannot access
another. To retire a set, remove its entry and reconverge; its route disappears.
Its private files can be retained for deliberate later reuse.

## Runtime

The managed label is io.arthack.agentstart.serve-mcp. Its public entrypoint is
agentstart mcp serve; agentstart mcp check validates the private configuration.
FastMCP dependencies are locked in uv.lock and installed with uv sync --frozen.
The transport is bound to loopback. Tailscale supplies HTTPS, while the gateway
checks bearer auth on every HTTP method and checks the request origin.

Each authenticated frontend session receives its own stdio backend processes.
Complete requests within that session are serialized, including discovery,
so a pending interaction keeps its original callback context. StatefulProxyClient
retains the native MCP connection, including image and structured results and
interaction callbacks, until the session closes or expires. Shutdown reaps
backends. Native connections start with MCP initialize, accommodating servers
that close on an unsupported sessionless discovery probe. The session idle
timeout defaults to 30 minutes.

The gateway requires MCP initialize/session semantics because Computer Use
maintains a REPL. Sessionless server/discover returns method-not-found so modern
clients negotiate the supported stateful protocol. It never silently creates
a new REPL for each request.

## Verify

    uv sync --frozen --project gateway
    gateway/.venv/bin/python -m unittest discover -s gateway -p 'test_*.py'
    python3 tests/mcp-install.py

Tests use disposable stdio fixtures and real loopback HTTP. They cover distinct
toolset auth, unlisted-call rejection, private resources/prompts, image and
structured-error fidelity, declined interactions, cancellation, independent
sessions, and child cleanup. Installer
tests cover private-file ownership, stable credentials, invalid configurations,
and preservation of unrelated Funnel routes.

### Verify the public path

A successful request from inside the tailnet does not verify Funnel ingress:
MagicDNS can resolve the hostname to its private Tailscale address. Resolve
the hostname through a public DNS resolver and probe each returned public IPv4
address with the original hostname for TLS and HTTP. For example, substitute
the node hostname and one address returned by `dig`:

```sh
dig @1.1.1.1 NODE.TAILNET.ts.net A +short
curl --noproxy '*' --resolve 'NODE.TAILNET.ts.net:443:PUBLIC_IPV4' \
  --connect-timeout 5 --max-time 15 --silent --show-error \
  --output /dev/null --write-out '%{http_code}\n' \
  https://NODE.TAILNET.ts.net/mcp/grok
```

The unauthenticated probe must complete normal certificate verification and
return 401. Then use the configured MCP client and its existing private
credential to verify `initialize`, `notifications/initialized`, and `tools/list`
from the external client machine. A 401 alone does not verify backend discovery.
The external client needs ordinary HTTPS, without installing Tailscale.

### Recover public TLS failures

On 2026-09-08, Greybird's public addresses accepted TCP and closed during TLS,
while private HTTPS and authenticated loopback MCP worked. The running daemon
and CLI were both 1.102.3; public probes did not increment `peerapi_ingress` in
`tailscale debug metrics`. Reapplying the existing mapping and briefly toggling
Funnel did not recover it. Removing only the 443 listener, waiting 20 seconds,
and recreating its original handlers restored public TLS on both addresses.
This is an observed recovery, not evidence of a specific upstream root cause.

Before repeating that recovery, save `tailscale serve status --json`, establish
ownership of every handler on 443, and account for the brief interruption of
those handlers. `tailscale funnel --https=443 off` removes the whole listener;
recreate every saved 443 handler with its exact backend using
`tailscale funnel --yes --bg --https=443 --set-path=PATH BACKEND`. Greybird had
`/` pointing to `http://127.0.0.1:8787` and `/mcp` pointing to
`http://127.0.0.1:4790/mcp`. Compare the complete configuration afterward with
the saved copy, including the other ports, then repeat the public checks above.
An unrestricted `funnel reset` would also remove independently owned Serve
routes. Ordinary installation must not interrupt healthy listeners to perform
this recovery, restart Tailscale, or rotate gateway credentials.
