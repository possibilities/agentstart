# Fleet Resources Advice Field Guide

An interactive guide to the advice AgentStart makes available in every managed
session. It organizes the fixed private fleet resources by intent, introduces useful
starting points, and makes each skill's playbook, supporting field notes, and
harness invocation easy to browse.

The guide includes canonical session guidance and plain-language summaries of
harness utilities. Their implementation files are counted for transparency but
are deliberately not copied into the site: this is a reader for operational
advice, not a source-code browser.

## Development

Requires Node.js `>=22.13.0`.

```bash
npm install
npm run dev
```

The development server refreshes `public/fleet-resources.json` from the installed
resources before it starts. Set `AGENTSTART_RESOURCES_ROOT` to snapshot a
different resource root. If no installed resource set is available, the generator
keeps the checked-in snapshot so clean checkouts and hosted builds remain
reproducible.

## Verification

```bash
npm run build
npm test
npm run lint
```

The tests cover the rendered field-guide shell and validate the checked-in
snapshot's advice coverage, category structure, utility summaries, and size.

## Hosting

The app is a vinext/Cloudflare Worker site configured for OpenAI Sites through
`.openai/hosting.json`. The resource guide is read-only and needs no D1 or R2 binding.
