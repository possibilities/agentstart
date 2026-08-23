# Common Pack Atlas

An interactive reader for AgentStart's installed `common` capability pack.
The site exposes the real pack contract, skills, supporting references,
guidance, and harness-specific resources in one searchable interface.

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

The tests cover the rendered atlas shell and validate the checked-in snapshot's
counts, required files, and path uniqueness.

## Hosting

The app is a vinext/Cloudflare Worker site configured for OpenAI Sites through
`.openai/hosting.json`. The pack is read-only and needs no D1 or R2 binding.
