# 0043: Install OpenCode 2 beside OpenCode 1

Accepted September 24, 2026.

AgentStart installs the empirically verified `@opencode/cli@2.0.16` package
under `~/.local/libexec/agentstart/opencode2` and publishes only
`~/.local/bin/opencode2`. The private npm prefix also contains a package-owned
`opencode` binary, but that prefix is never added to PATH. The existing
`opencode` command and its configuration and sessions remain untouched.

The helper is called by full `scripts/install.sh --install`, owns its prefix
through an explicit marker, refuses foreign commands and directories, verifies
the package and both executable versions, and checks that the original
`opencode` path and version remain the same. The pin moves only after the new
release is checked with AgentRoles' V2 prompt, skill, MCP and TUI delivery.
AgentRoles also recognizes the `opencode2` name and probes the executable it
will launch, so the two names retain independent role behavior.

This creates a reversible side-by-side command, not a V1-to-V2 migration.
Automatic full convergence must not replace either name with the other. A
later default-command cutover is a separate decision.

Evidence: `scripts/install-opencode2`, `scripts/install.sh`,
`tests/install-opencode2.test.ts`, and AgentRoles
`docs/adr/0007-deliver-roles-to-both-opencode-majors.md`.
