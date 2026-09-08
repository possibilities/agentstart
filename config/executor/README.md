# Executor delivery

AgentStart owns `integrations.json`: the MCP registrations needed by managed
fleet workflows. The full installer calls `scripts/executor-integrations
--install` after installing their commands. The signed Executor CLI's stdio
MCP mode talks to the existing vendor-owned service; this adds no daemon, competing service,
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
  connection creation. An absent fleet checkout skips its registration.

Every registration is inspected before catalog writes begin. An exact existing
registration can be adopted without altering it. Successful convergence records
its non-secret configuration at
`~/.local/share/agentstart/executor-integrations.json`. A later source change
can replace an unchanged, receipt-proved registration only when all its
connections are the managed no-auth default. Independent config drift,
credential templates, and additional connections prevent replacement. Catalog
changes recheck this state immediately before mutation. Failed discovery leaves
an incomplete result that the next explicit install can finish; it never
records success. Removing an entry from the `servers` list alone does not
delete its registration.

`retiredServers` explicitly names a retired integration and its last source
configuration. Retirement requires that exact current configuration, a matching
ownership receipt, and only the unauthenticated managed default connection
(or no connections). It refuses drift or independent credentials before any
catalog write, rechecks immediately before removal, and verifies absence before
dropping the receipt entry. `--verify` reports a surviving retired registration.
This is the narrow migration guard for the former Gog registration; it cannot
remove or replace either authenticated `google_gmail` connection.

Unlisted integrations and accounts are untouched. The source contains no
credentials. Underlying tools retain their existing authentication stores;
the computer-use adapter receives only the real Codex home as a path setting.
Use a serialized installation window when other agents are changing shared
configuration. Content-only and six-hour skill syncs never reconcile the
Executor catalog or restart its service.

## Installer approvals

The installer uses structured MCP `execute` and `resume` results. Executor's
human CLI prints approval pauses as prose and exits zero, so its `call` output
is not a reliable JSON protocol for convergence.

An explicit `--install` authorizes the manifest's guarded registry operations.
When one of those operations pauses, the installer accepts only its exact tool
address, arguments, empty confirmation schema, and known registry confirmation
message. It accepts at most one confirmation per call. A different operation,
changed arguments, extra approval terms, a custom policy prompt, or a nested
interaction causes cancellation of that execution and stops convergence.
This never changes Executor's approval policies or approves application access.

Before any resume, the execution ID and intended action are appended to the
private `executor-integrations.json.executions.jsonl` beside the ownership
receipt. Append refuses symlinks, non-regular files, hardlinks, other owners,
and existing permissions other than `0600`; it uses `O_NOFOLLOW` where
available and checks the opened file's identity before writing. The journal
contains no upstream payloads or credentials. A failed
resume preserves that record and reports the ID; inspect its outcome before
retrying. Verification sends no approvals and reports an unexpected pause's ID
without writing ownership or execution receipts. Closing the stdio client does
not restart the shared service.

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

Gmail uses the independently authenticated `google_gmail` connections already
in Executor. The `email` skill selects the intended account and uses discovered
read, draft, send, and attachment tools. AgentStart never creates a replacement
account or copies its credentials. Other Google products require their own
available integrations and workflow skills.

Terminal Control operates existing named sessions but does not create them
through MCP. Preserve that session-creation workflow until an MCP implementation
exists. Exposing write tools does not authorize unsolicited writes or messages.

Attention exposes its 12 contract-derived producer tools for durable handoffs,
bounded waits, inspection, and scoped cancellation. Human claims, resolutions,
returns, and credential administration stay with the operator. MCP cancellation
stops an outstanding wait or event stream without withdrawing the item. Use
paged events when the aggregator does not forward logging notifications.
The `attention` skill carries payload, exact-browser-target, and outcome rules;
ordinary in-session clarification can still use native harness questions.

Sounds exposes `notify` and `guide` through the CLI's shared typed handlers.
Playback is audible by default; use `no-play:true` for silent preparation.
Keep `data.patch` as a recipe using native file tools, and use absolute recipe
and WAV paths. Cancellation and stdio shutdown stop active playback without
removing recipes or exports. Its checkout owns command installation; the
fleet installer invokes that contract and preserves existing Bun links.

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
