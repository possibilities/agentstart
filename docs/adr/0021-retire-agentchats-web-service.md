# 0021: Retire the AgentChats web service and preserve terminal access

Accepted September 15, 2026. AgentChats no longer owns a web transcript UI.
Its CLI, OpenTUI resume picker, transcript index, native resume output, and
stdio MCP remain supported.

AgentStart removes `io.arthack.agentchats.serve` from the active launch-service
manifest and deletes its service template. During a bounded cleanup window, the
old label remains selectable through `scripts/install-launchagents --service`.
Check mode reports the exact target without mutation. Install mode may boot out
and delete only a regular plist whose second line is the original exact
AgentStart ownership marker; symlinks and foreign occupants are refused.

This cleanup is separate from AgentChats installation. AgentStart continues to
invoke the checkout-owned installer so the command, index, OpenTUI picker,
skill, and MCP stay available. AgentSurface's Herdr plugin entrypoint and
`prefix+h` binding are unchanged.

Evidence: [launch-service installer](../../scripts/install-launchagents),
[retirement tests](../../tests/install-launchagents.sh), and the
[fleet map](../../skills/fleet/MAP.md).
