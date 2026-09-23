# Agent interface policy

Every agent-facing workflow has one authoritative operating surface. Choose
the surface from the work itself: use MCP for structured actions an agent must
invoke across processes, the native harness for behavior the harness already
owns, and an owning CLI or TUI for local or interactive work. A skill explains
how to use that surface; its existence does not imply that another MCP server
is needed.

The fixed MCP inventory is `config/resources/mcp-servers.json`. The active
role and harness own delegation, questions, approvals, and task state. CLI and
TUI contracts remain supported when interaction, terminal state, or a narrow
skill-local helper is the product. Skill names and descriptions provide
discovery, so this matrix is an engineering support contract rather than a
second prompt catalog.

| Workflow | Authoritative surface | Why |
| --- | --- | --- |
| Browser automation | `agent-browser` and AgentBrowse MCPs | Typed browser actions, durable sessions, and handoff targets cross process boundaries. |
| Durable work, memory, research, and authored knowledge | AgentHUD, AgentBrain, AgentChats, AgentSearch, AgentScrape, and AgentWiki MCPs | Structured reads and writes are useful in every managed session. Legacy Board history remains outside the active MCP inventory. |
| Desktop control, human handoff, cross-session messages, keyboard audit, Grok Bot, sounds, and terminal control | Agentdesk, AgentAttention, AgentSurface, AgentKeys, AgentGrok, AgentSounds, and Terminal Control MCPs | Each owner exposes its agent command contract as typed tools. |
| Gmail | Account-bound Gog MCPs for semantic reads; Gog CLI for sends, drafts, exact MIME, and complete pagination | The two surfaces share Gog authentication and divide work at their current schema boundary. |
| shadcn registry work | Fleet shadcn MCP | The fixed registry configuration must be independent of the caller's project directory. |
| Delegation, model choice, questions, approvals, and task lifecycle | Native Claude Code or Codex mechanisms selected by the active role | The harness already owns execution state and permission semantics. |
| Herdr sessions, Hunk review, Plannotator review, AgentRoles launches, and operator notification | Owning CLI or TUI, guided by its skill | These workflows are interactive, terminal-bound, or intentionally process-local. |
| Fork maintenance and inactive-worktree tending | Skill-local scripts plus native Git and Herdr commands | The scripts are deterministic implementation contracts within the workflow, not general remote services. |

When a surface changes, update this file and any affected edge in
`skills/fleet/MAP.md` in the same commit. Add a new MCP only when a workflow
needs a stable typed cross-process contract that its current surface cannot
provide.

AgentNotify is a deliberate parity interface: `agentnotify` preserves terminal-notifier CLI behavior, while the native app’s private Unix socket and stdio MCP expose the same durable notification operations. AgentStart installs a `~/.local/bin/terminal-notifier` router through `install-harness-shims`, ahead of Homebrew on the fleet PATH. The installer refuses to proceed while Homebrew terminal-notifier remains linked at a standard prefix, because an absolute-path or differently ordered caller could bypass the router and post a macOS banner. The router checks AgentNotify availability before dispatch and fails with status 127 without submitting anything when it is unavailable. After dispatch, it preserves the result without retrying because durable acceptance is the success boundary. AgentNotify’s inbox and sticky arrival preview are its complete presentation path: it never requests system-notification authorization or posts macOS banners, sounds, categories, or Notification Center entries. Its one-time setup offer, Preferences button, and shared `installShim` operation delegate to that same `scripts/install-notification-shim` owner for explicit installation. Funk uses the managed path for notifications and verifies the own-arrivals-only policy without creating a durable probe item. Explicit vendored upstream binaries bypass a PATH shim and are outside this compatibility contract; ordinary callers should use the router. `skills/notifications` in AgentNotify owns expert usage; the older `notify` skill directs callers there. Explicit roles and AgentVoice receive its full contract through the shared inventory, including durable appearance preferences; no separate prompt tool catalog or per-client notification registry is needed. The app starts on demand; installation never restarts a running inbox.
