# 0002: Compose capabilities without moving native stores

AgentStart installs portable resources as capability packs under
`~/.local/share/agentstart/capabilities`; AgentLaunch composes immutable
session projections and injects them through each harness's native extension
surface. Claude receives a synthetic plugin named `agent`, Codex receives
standalone extra skill roots plus exact `skills.config` policy through a
caller-owned foreground App Server, and Pi receives explicit resource paths.
That Codex policy name-disables every `$agent:<skill>` from the compatibility
projection while path-enabling the selected bare skills; plugin enablement is
persistent user/profile policy in Codex and cannot be scoped with a session
flag.
The Codex server is account-pinned through codex-swap's ordinary `run`/lease
contract and exists only for its native remote TUI. Native configuration and
session stores remain canonical, so
native resume, cross-account resume, cass indexing, and harness history keep
one source of truth; Codex desktop and other unmanaged clients use the
temporary compatibility plugin rendered from `common`.
