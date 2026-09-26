---
name: zen-open
description: Open a URL in a named Zen browser container with the zen-open CLI. Use when asked to open a site "in a container", to keep a site inside a specific Firefox/Zen contextual identity, or to list the browser's containers.
---

# zen-open

`zen-open <container> <url>` opens a URL in the named Zen container through
the managed `ext+container:` protocol handler. AgentStart's managed
`policies.json` force-installs the handler extension into Zen and
pre-authorizes the scheme, so the call does not stop on a confirmation
dialog.

- `zen-open --list` prints the container names in the default profile.
- `<container>` matches a name exactly, then case-insensitively, then as a
  substring — `zen-open account-2 https://github.com` resolves
  `account-2 (notimpossiblemike@gmail.com)`. An ambiguous match fails and
  lists the candidates.
- The extension is force-installed at Zen startup. If `zen-open` warns that
  the handler is not in the profile yet, the browser needs one restart after
  the policy first landed.
- `zen-usage` (no arguments) is the destructive reset: it quits Zen, writes a
  replacement session file whose tabs carry fixed labels (`zenStaticLabel`)
  and container assignments, and relaunches so session restore materializes
  the declared usage-dashboard set — five named dashboard tabs plus three
  named about:blank container tabs, below Zen's own top new-tab slot. Run it
  only when wiping every open tab is intended.
- Zen (the application) is the machine layer's Brewfile cask; only the
  container-open capability is AgentStart's.
