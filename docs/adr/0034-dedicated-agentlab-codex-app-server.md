# 0034: Keep AgentLab's Codex daemon separate

Accepted September 19, 2026. AgentLab needs a reconnectable Codex app-server,
but its application runtime must not own the daemon lifecycle or reuse an
AgentVoice endpoint.

AgentStart owns `io.arthack.agentlab.codex-app-server`, a resident user
LaunchAgent that runs the installed `codex app-server` on one private Unix
socket under AgentLab's state directory. The socket identity is stable and
configurable from AgentLab's endpoint registry. AgentLab connects as a client;
it does not spawn, stop, restart, install, authenticate, or claim filesystem
and sandbox authority for the daemon.

The service is independently selectable and independently observable. Its
readiness contract is deliberately narrow: launchd state is running and the
Unix socket exists. Status never connects to the daemon, so an operator can
inspect service readiness without creating a Codex connection or touching
credentials. Installation or activation is a later operator action and is not
performed by the AgentLab application.

This keeps AgentVoice and AgentLab failure domains and session identities
separate while preserving one lifecycle owner for each service.
