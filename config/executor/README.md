# Executor delivery

AgentStart owns `integrations.json`: the MCP registrations needed by managed
fleet workflows. The full installer calls `scripts/executor-integrations
--install` after installing their commands. The signed Executor CLI talks to
the existing vendor-owned service; this adds no daemon, competing service,
global harness configuration, or copy of Executor's private database.

`config/resources/mcp-servers.json` delivers one Executor stdio connection to
each managed Claude/Codex session. Executor discovers downstream tools on
demand. Native workflow skills remain in the harness. Shadcn remains a direct
session MCP because its operations depend on the project's working directory;
a shared daemon must not silently substitute its own cwd.

## Convergence and ownership

- `scripts/executor-integrations --check` prints the source plan offline.
- `scripts/executor-integrations --verify` reads registered configurations and
  default connections without refreshing tools or changing configuration.
- `--install` creates missing registrations, ensures a no-auth `org/default`
  connection, and refreshes and verifies each tool catalog. It supports both
  Executor versions that auto-connect stdio and those that require explicit
  connection creation. An absent fleet checkout skips its registration; Gog
  is optional when its independently installed executable is absent.

Every registration is inspected before catalog writes begin. An exact existing
registration can be adopted without altering it. Successful convergence records
its non-secret configuration at
`~/.local/share/agentstart/executor-integrations.json`. A later source change
can replace an unchanged, receipt-proved registration only when all its
connections are the managed no-auth default. Independent config drift,
credential templates, and additional connections prevent replacement. Catalog
changes recheck this state immediately before mutation. Failed discovery leaves
an incomplete result that the next explicit install can finish; it never
records success. Removing a manifest entry does not delete its registration.

Unlisted integrations and accounts are untouched. The source contains no
credentials. Underlying tools retain their existing authentication stores;
the computer-use adapter receives only the real Codex home as a path setting.
Use a serialized installation window when other agents are changing shared
configuration. Content-only and six-hour skill syncs never reconcile the
Executor catalog or restart its service.

## Workflow boundaries

Use the exact paths returned by Executor's `tools.search` and
`tools.describe.tool`; owner and connection names are deployment data. Its
`skills` tool documents Executor itself, while native skill discovery supplies
the fleet workflows. The fleet `guide` tools expose shared command contracts
when an aggregator does not forward MCP initialization instructions.

Native filesystem, shell, image-reading, and collaboration tools remain useful.
A shared MCP process does not inherit a calling agent's cwd or session identity;
pass absolute paths and explicit resource/session identifiers when applicable.
In particular, every agent-browser call must carry the same selected `session`.
AgentBrowse owns durable browser targets and profiles; agent-browser operates
pages. Registering its full MCP catalog does not change those responsibilities.

The current third-party catalogs have real limits: Gog exposes Google reads and
document/sheet writes, but no mail-send tool; Terminal Control operates existing
named sessions but does not create them through MCP. Preserve their existing
workflows until the missing operations have an MCP implementation. Exposing
write tools does not authorize unsolicited writes or messages.

Codex computer use is available, but replacing Peekaboo also requires usable
normal-window capture and input validation. The installed adapter returns
screenshot file URLs inside text JSON, so agents must load them with the native
image reader. Do not mistake a returned path or JSON object for a viewed image.
Tool registration itself grants no application consent.

## Results through Executor

An executed downstream call returns `{ok:true,data:<MCP result>}` on success.
Fleet JSON envelopes live in `data.structuredContent` and a standalone JSON
text block. Plain text/Markdown stays text. A domain error currently becomes
`{ok:false,error:{code:"mcp_tool_error",details:{content:[...]}}}` in Executor:
parse the separate JSON text block to recover the original domain code and
recovery. Never slice JSON out of a prose message or treat an outer successful
execution as evidence that every downstream call succeeded.

When upstream content contains actual image blocks, explicitly emit them from
Executor's execution. Returning an image-shaped object only returns JSON.
