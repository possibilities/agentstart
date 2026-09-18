# 0031: Use AGENTS.md for harness guidance

Status: Accepted, 2026-09-18.

AgentStart publishes one deliberately empty canonical guidance source and
links it into both harness homes as `AGENTS.md`: `~/.claude/AGENTS.md` and
`~/.codex/AGENTS.md`. Repository guidance likewise has one root entrypoint,
`AGENTS.md`.

The earlier Claude-specific `CLAUDE.md` alias duplicated the discovery surface
without adding meaning. Default convergence now removes the exact retired
global link previously owned by AgentStart after creating the two current
links. It refuses to remove a differently targeted symlink and leaves an
independent regular file alone, because neither is proven installer-owned.
Repository aliases are deleted from current projects and validators keep them
from returning.

The canonical content contract is unchanged: both global links resolve to
`~/.local/share/agentstart/resources/guidance/AGENTS.md`, while substantive
operator guidance continues to render through AgentGuidance's extension
prompts.

Evidence: [installer](../../scripts/install.sh),
[installer validation](../../tests/validate.sh), and
[operator guidance](../../prompts/agentguidance/GUIDELINES.md).
