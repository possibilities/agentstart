# Common Pack Advice Field Guide

An interactive guide to the advice AgentStart makes available in every managed
session. It organizes the `common` capability pack by intent, introduces useful
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

The development server refreshes `public/common-pack.json` from the installed
pack before it starts. Set `AGENTSTART_CAPABILITIES_ROOT` to snapshot a
different capability root. If no installed pack is available, the generator
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
`.openai/hosting.json`. The pack is read-only and needs no D1 or R2 binding.
