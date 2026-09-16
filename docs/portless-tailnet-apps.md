# Portless apps over Tailscale

AgentStart's supervised AgentVoice, AgentVoice test and AgentHUD readers opt in to
Portless's tailnet-only sharing. Their usual local URLs remain unchanged:

- `https://agentvoice.localhost`
- `https://agentvoice-test.localhost`
- `https://agenthud.localhost`

Portless also registers one root-mounted HTTPS URL per running app on this
machine's Tailscale DNS name. Tailscale Serve has one hostname, so additional
apps use additional HTTPS ports rather than app-name subdomains. Find the current
mapping instead of guessing it:

```sh
portless list
tailscale serve status
```

On any device signed in to the same tailnet, open the `tailscale:` URL shown
under the app. For example, the output may show
`https://greybird.example.ts.net:8443`. Portless keeps the local and tailnet URLs
active together and removes only the app's own Serve registration when that app
stops. Ports are allocated from the currently free Serve ports, so use
`portless list` again after a machine boot or coordinated multi-service restart.

For an ordinary foreground Portless app, opt in explicitly:

```sh
portless my-app --tailscale <command>
# equivalent for a trusted launcher:
PORTLESS_TAILSCALE=1 portless my-app <command>
```

The app receives its exact remote origin as `PORTLESS_TAILSCALE_URL`. Fleet apps
accept only that injected HTTPS origin, keep their listeners on loopback, and
continue exact Host/Origin checks. Tailscale must be connected, MagicDNS and
HTTPS certificates must be enabled, and the client device must be on the same
tailnet. `portless doctor` checks the local proxy; `tailscale status --json`
reports the tailnet state.

This workflow does **not** use Tailscale Funnel. `--funnel` and
`PORTLESS_FUNNEL=1` publish to the public internet and are outside this contract.
The pre-existing webhook Funnel route on this machine is separate and must not
be reset or replaced while managing these app routes.
