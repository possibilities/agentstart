# ADR 0026: Share supervised Portless apps on the tailnet

Status: accepted on 2026-09-16.

## Decision

AgentVoice and AgentHUD own an explicit `serve --tailscale` capability. It keeps
their fixed `.localhost` route and adds Portless's tailnet-only Tailscale Serve
route. AgentStart enables that option for the supervised production reader, test
reader and HUD.

Each child trusts only the exact HTTPS `PORTLESS_TAILSCALE_URL` injected by
Portless after route registration. Vite's host, same-origin and websocket policy
admits that origin beside the fixed local origin. Listener binding remains
loopback-only. Funnel, ngrok, LAN and wildcard routing remain disabled.

Portless owns route allocation and cleanup. The operator discovers the current
root-mounted machine URL and port with `portless list`; app-name subdomains are
not synthesized. AgentStart does not reset or replace unrelated Tailscale Serve
or Funnel configuration.

## Why

The apps already use Portless and Tailscale supplies authenticated device reach.
Using the supported Portless integration preserves localhost behavior and route
lifecycle. Allowing ambient tunnel variables would weaken the apps' deliberate
network boundary, while a second reverse-proxy implementation would duplicate
Portless and complicate exact-origin enforcement.

## Consequences

Remote devices must join the tailnet, and allocated HTTPS ports can change after
a coordinated cold start. `portless list` is therefore the source of truth.
Public sharing remains a separate, explicitly unauthorized operation.
