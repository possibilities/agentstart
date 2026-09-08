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
| Planning, memory, research, and authored knowledge | AgentBoard, AgentBrain, AgentChats, AgentSearch, AgentScrape, and AgentWiki MCPs | Structured reads and writes are useful in every managed session and in authenticated HTTP toolsets. |
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
