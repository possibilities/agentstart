# Agentbrain private share ingress

AgentStart owns the resident share job and its dedicated Tailscale TCP frontend.
Agentbrain owns the HTTP API, bearer token, durable ledger and clients. The
[decision](adr/0052-loopback-agentbrain-share-with-private-tcp-serve.md) preserves
the current Chrome/Android HTTP endpoint without changing a client or credential:

```text
existing client HTTP origin :8787
  -> encrypted tailnet -> Tailscale Serve TCP :8787
  -> 127.0.0.1:8787 -> Agentbrain bearer-authenticated share APIs
```

No listener binds LAN, wildcard or the application's Tailscale interface. The
old `AGENTSTART_INSTALL_SHARE_HOST` override no longer chooses a bind address;
the supervised bind is fixed. First installation waits for a connected tailnet;
an installed job is retained while offline. If Tailscale cannot be inspected,
cutover fails without replacing the old job. Agentbrain's original runbook
describes its direct CLI bind; this procedure owns the newer supervised topology.

## Bounded initial cutover

The operator must own the share restart and route edits. Do not run a full
installer first: retirement of the stale public route must precede any loopback
cutover. Preserve all unrelated routes, especially Omajot's 8448 handler to
loopback 8799 and AgentVoice's endpoints. Never use Serve/Funnel `reset`,
`set-config`, a whole-port HTTPS shutdown, or a full configuration replacement.

1. Save the existing owned share plist and Serve JSON to restrictive **local**
   rollback/evidence files. Do not print or commit device names, URL identities,
   or private state. Prove the plist is a regular non-symlink with the exact
   template-position ownership marker. Verify the existing authenticated share
   health probe through the operator's already established credential path;
   do not reveal or rotate the token.
2. Inspect the retained HTTPS 443 root route. Only when its exact `/` handler is
   `{"Proxy":"http://127.0.0.1:8787"}` with Funnel enabled and the archived Source
   owner is confirmed, remove that **one** handler:

   ```sh
   tailscale funnel --yes --https=443 --set-path=/ off
   ```

   Compare before/after JSON: only the selected handler may disappear, with its
   Web/TCP/Funnel containers removed if now empty. Every unrelated handler,
   frontend, foreground session and service must compare unchanged. If the
   handler differs or state moves concurrently, stop and resolve ownership.
   The installer refuses to perform this retirement for you.
3. For a retained `io.arthack.agentstart.serve-mcp` job, verify a regular
   non-symlink plist, the exact installer marker at the original position, and
   the original `agentstart mcp serve` command identity. Boot out only
   `gui/$(id -u)/io.arthack.agentstart.serve-mcp`, verify it is no longer loaded,
   and remove only that owned plist. Preserve private configuration, credentials,
   records and session state. A remaining public `/mcp` handler requires its own
   exact ownership-checked retirement under ADR 0007, never a broad reset.
4. From the deployed AgentStart checkout, run the supported exact-label path:

   ```sh
   scripts/install-launchagents --check --service io.arthack.agentbrain.share
   scripts/install-launchagents --install --service io.arthack.agentbrain.share
   scripts/install-launchagents --status --service io.arthack.agentbrain.share
   ```

   Preflight checks public/foreign route conflicts **before** rewriting the
   service. Changed owned jobs are booted out and bootstrapped once. The network
   helper proves that launchd's PID owns only `127.0.0.1:8787`, then checks
   unauthenticated `GET /v1/health`, `POST /v1/share` (no body), and
   `GET /v1/shares` return the Agentbrain `401 unauthorized` envelope. Only then
   may it run `tailscale serve --bg --tcp=8787 tcp://127.0.0.1:8787`. Curl's
   personal configuration and ambient proxies are disabled for these probes,
   so neither can inject a credential or redirect the proof elsewhere.
5. Verify the local and existing tailnet client endpoint with the operator's
   established authenticated health probe, plus unauthenticated rejection.
   Confirm the share process no longer holds any Tailscale/LAN listener and no
   public route targets backend 8787. Compare unrelated routes to the saved
   snapshot. No phone access is necessary. A client share proof, if separately
   requested, remains an explicit operator/client action.
6. Rerun exact-label installation. The running PID, plist inode/mtime and matching
   Serve route must remain unchanged. Complete required full installation and
   role-output convergence under the parent task's authority. Protect active
   AgentVoice services with its existing preservation option when their restart
   is not authorized; network hardening does not grant unrelated restarts.

## Failure and rollback

Conflicts fail before listener changes. Missing readiness/authentication fails
before **new** private route publication. A failed command or postcondition is
not safe to blind-retry: inspect current Serve state first. The helper reports
sanitized errors and never prints subprocess output, tokens or live identities.
It cannot repair or overwrite a concurrently changed foreign route.

Prefer a fail-closed rollback: retain the loopback backend and withdraw only
the dedicated private TCP frontend. First verify the current background TCP
8787 handler is exactly `{"TCPForward":"127.0.0.1:8787"}`, with no foreground
8787 occupant or Funnel exposure. Then:

```sh
tailscale serve --tcp=8787 off
```

Verify the after snapshot is precisely the before snapshot minus `.TCP["8787"]`
(and an empty TCP container, if applicable). Do not change other routes. Ordinary
convergence republishes the route only when the backend proof passes.

If the operator needs the former direct tailnet listener back, remove the private
frontend first, prove the retired public backend route remains absent, then
restore the saved owned share plist and boot out/bootstrap only that share job.
The saved plist contains generated local addressing; do not put it in Git.
This restores the prior topology and is not a new durable installer policy.
Never restore the public Source/MCP routes or rotate the share token as rollback.
