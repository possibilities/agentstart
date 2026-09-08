# Terminal Control

Use Terminal Control for a real terminal application's visible screen, input,
and readiness. In managed sessions, discover its MCP tools through Executor.
Use the native shell for the CLI operations that the installed MCP omits.

## Discover and choose a session

In Executor:

```js
const found = await tools.search({ namespace: "termctrl", limit: 30 });
return found;
```

Describe the returned path with `tools.describe.tool({ path })`, then call
`tools[path](args)`. Use `list_sessions` to find a running session and
`get_session_status({ name })` to verify its command, working directory, and
state before driving it. Pass an absolute `cwd` when filtering: the shared
server's directory is not the caller's project. Use one exact session name
throughout an interaction, and preserve another person's running session.

The current MCP has no session creation tool. For a new session, run the
installed CLI through the native shell, choosing an owned, unique name:

```sh
termctrl start NAME --cwd /absolute/project -- my-terminal-app
```

For an OpenTUI application, add `--host opentui` before `--`. For an
application the human will drive in their terminal, use `termctrl run` in that
terminal. Read the [version-matched CLI reference](terminal-control-cli.md)
for launch flags, human attachment, or operations absent from MCP.

## Observe, interact, verify

`get_screen({ name })` reads the current visible screen immediately. Treat
that screen as the evidence for a full-screen TUI; retained logs are not its
visible state. For a known transition, use the discovered `interact` path:

```js
return await tools[interactPath]({
  name: sessionName,
  input: [{ type: "text", text: "help" }, { type: "key", key: "enter" }],
  waitFor: "Commands",
  timeoutMs: 5000
});
```

`interact` sends ordered input, waits for the requested visible text, and
returns the resulting screen. Use a bounded wait instead of sleeps. To wait
without typing, pass `input: []`. Choose `send_input` for input alone. Use
typed keys and controls from the live schema, such as `arrowDown` or
`{ type: "control", letter: "c" }`; do not translate CLI key atoms into MCP
arguments. Add pacing only when deliberately demonstrating slow typing.

Use `resize_session` for more visible area. `send_mouse` takes zero-based
cells within that viewport; the application must enable mouse reporting.
Never inject raw mouse escape sequences to work around disabled reporting.

Check Executor's outer `ok`. Successful screens are in
`data.structuredContent.text`; inspect the returned content for other tool
results. On failure, preserve the message and `error.details.content` instead
of treating an empty result as success. After an uncertain input delivery,
read the screen before retrying a non-idempotent action.

## Evidence and cleanup

For a needed visual check, call `save_screen` with the exact session `name`
and an absolute PNG `path`. It returns the saved path, not an inline image;
open it with the harness's native image viewer. Retain terminal text, images,
arguments, and recordings only when needed for the task.

Stop an owned test session with `stop_session({ name })` when finished,
including after a failed check, unless the user asked to keep it running.
Confirm it is no longer running. Do not stop a session merely because it
appears in discovery.

MCP also omits CLI restart, retained logs, semantic/text exports, recording,
markers, and video editing. Use the [CLI reference](terminal-control-cli.md)
for those features. If a tool is absent or its schema unavailable, inspect the
installed CLI help; report the coverage gap instead of inventing an MCP verb.
