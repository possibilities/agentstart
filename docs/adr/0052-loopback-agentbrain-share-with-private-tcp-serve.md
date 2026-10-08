# 0052: Keep Agentbrain share on loopback behind private TCP Serve

Accepted October 7, 2026. Extends the loopback/private-Serve boundary in
[ADR 0026](0026-share-portless-apps-on-the-tailnet.md). Supersedes AgentStart's
direct tailnet bind for the share service, not Agentbrain's authenticated
share-ingest-v1 API or Chrome/Android endpoint contract. Agentbrain's source
contracts remain `~/code/agentbrain/docs/adr/0017-authenticated-share-ingress.md`
and `~/code/agentbrain/docs/contracts/share-ingest-v1.md`.

AgentStart supervises `agentbrain share serve --host 127.0.0.1 --port 8787` and
converges a background, tailnet-only raw TCP Serve frontend on 8787 forwarding
to `127.0.0.1:8787`. Existing clients keep their HTTP origin, port, paths and
bearer token. This is the private ingress, not a deprecated alias. No new HTTPS
endpoint, public Funnel, Agentbrain CLI change or phone deployment is needed.
Tailscale 1.102.4's `--tcp` contract and matching
[`ipn/serve.go`](https://github.com/tailscale/tailscale/blob/v1.102.4/ipn/serve.go) /
[`cmd/tailscale/cli/serve_v2.go`](https://github.com/tailscale/tailscale/blob/v1.102.4/cmd/tailscale/cli/serve_v2.go)
implement byte forwarding without TLS termination
or PROXY headers. Tailnet transport remains encrypted; the application still
authenticates each data/health request.

Preflight refuses any public Funnel route to backend 8787, public frontend
8787, foreign node TCP/Web handler on 8787, or foreground occupant. It runs
before replacing/loading the loopback service: the retained Source Funnel root
would become live again at that instant otherwise. The Source owner is archived
by [ADR 0049](0049-retire-archived-fleet-checkouts.md); the HTTP MCP gateway was
retired by [ADR 0007](0007-retire-http-mcp-gateway.md). Their bounded runtime
cleanup belongs to the operator, not new permanent installer branches.

Before publication, convergence proves the supervised process listens only on
loopback 8787 and all three share APIs reject requests without authorization.
It never reads or rotates the credential. It adds only the dedicated TCP
handler through the supported CLI and checks the entire postcondition, including
unchanged Omajot, AgentVoice, foreground, service and Funnel configuration.
Matching routes are not republished; identical loaded plists are not rewritten
or restarted. Unavailable Tailscale inspection blocks cutover rather than
guessing that old public routes are absent.

First activation still waits for a connected tailnet, matching the existing
installer's automatic discovery boundary. An owned service remains loopback-only
while the tailnet is offline; route publication is deferred until ordinary
connected convergence. Service status reports unavailable ingress or route drift.
No machine name, tailnet address, client URL, token or new private receipt is
tracked. See the [operator procedure](../agentbrain-share-ingress.md) for exact
cutover and fail-closed rollback.
