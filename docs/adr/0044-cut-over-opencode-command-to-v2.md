# 0044: Cut over the OpenCode command to V2

Accepted September 24, 2026. Supersedes the side-by-side command and
no-cutover policy in [ADR 0043](0043-install-opencode-2-beside-1.md).

AgentStart retains the verified `@opencode/cli@2.0.16` private npm prefix but
publishes its V2 executable as `~/.local/bin/opencode`, ahead of the legacy
`~/.opencode/bin/opencode` in the account's PATH. It removes only its own former
`~/.local/bin/opencode2` link after verifying the new command. Reusing the
existing private prefix avoids replacing files a currently running V2 session
may still load. Installer preflight refuses foreign commands and an unexpected
legacy executable, and repeated installation does not rewrite the already
verified npm package.

The V1 executable stays on disk until all existing V1 sessions have ended;
neither the installer nor the cutover removes configuration, credentials or
session history. AgentRoles ADR 0008
removes V1 rendering and the `opencode2` alias. No active agent is restarted
as part of this change.

The temporary executable-retention condition is superseded by [ADR 0046](0046-retire-opencode-v1-executable.md); user data and running processes remain preserved.
