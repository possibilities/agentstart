# 0020: Install Pi with an explicit npm action

Accepted September 15, 2026. Full convergence exposed Pi's action menu even
without a controlling terminal and then silently selected its reinstall
default. The operator requested that installation choose its action explicitly
without presenting or answering a menu.

## Decision

AgentStart installs or updates the bare Pi CLI through a dedicated helper that
runs the exact npm action published by Pi's upstream installer:

```sh
npm install -g --ignore-scripts --min-release-age=0 \
  --no-fund --no-audit --loglevel=error --progress=false \
  @earendil-works/pi-coding-agent
```

When npm's global prefix is not writable and does not already contain Pi, the
helper supplies `--prefix "$HOME/.local"`, matching upstream's fallback. It
refuses a conflicting executable, enforces upstream's Node.js 22.19.0 floor,
and verifies the npm package, executable path, and command version after the
install. The unversioned package follows npm's `latest` tag, preserving the
official installer's moving-release behavior.

AgentStart does not invoke the vendor installer, synthesize a terminal, pipe an
answer, send a key, or depend on its implicit default. Pi remains a bare CLI:
there are no Pi MCPs, skills, extensions, guidance, Herdr integration, or
AgentLaunch support.

## Consequences

Full convergence cannot display or silently accept Pi's install/reinstall/
uninstall choice. npm failures retain their exit status, and apparent success
without the expected package and executable fails verification. The direct npm
operation is not atomic and can still reinstall unchanged dependencies on each
full convergence; those are properties of the same upstream npm action, now
made explicit and independently testable.

Focused fixtures exercise the global and user-local prefix paths, exact argv,
preflight, failure propagation, verification, and the absence of prompt or
fleet-integration mechanisms without executing a live Pi installer.
