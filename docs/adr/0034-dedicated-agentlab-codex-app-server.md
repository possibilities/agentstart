# 0034: Keep AgentLab's Codex daemon separate

Accepted September 19, 2026. AgentLab needs a reconnectable Codex app-server,
but its application runtime must not own the daemon lifecycle or reuse an
AgentVoice endpoint.

AgentStart owns `io.arthack.agentlab.codex-app-server`, a resident user
LaunchAgent that runs the installed `codex app-server` on one private Unix
socket under AgentLab's state directory. The socket identity is stable and
configurable only at the AgentStart installer boundary. AgentStart renders that
same `unix://` identity into the separately supervised AgentLab server's
environment, converging the daemon before the console. AgentLab connects as a client;
it does not spawn, stop, restart, install, authenticate, or claim filesystem
and sandbox authority for the daemon.

The browser does not send, select, or receive the endpoint. The AgentLab server
alone converts the injected value into its endpoint registry and performs the
stock WebSocket-over-Unix `initialize`/`initialized` handshake before reading
the paginated model catalog. AgentVoice's endpoint and process are never
consulted.

The service is independently selectable and independently observable. Its
readiness contract is deliberately narrow: launchd state is running and the
Unix socket exists. Status never connects to the daemon, so an operator can
inspect service readiness without creating a Codex connection or touching
credentials. Installation or activation is a later operator action and is not
performed by the AgentLab application.

A targeted console convergence preserves the daemon's installed `--listen`
value and never reloads the daemon. An installer socket override is desired
state only when the daemon itself is part of the convergence; console-only
convergence and both services' status use the exact owned installed identity.
If both jobs require an explicit restart, the supported order is daemon
readiness first, then console readiness. This prevents a newly loaded console
from advertising an endpoint whose owner has not yet converged.

This keeps AgentVoice and AgentLab failure domains and session identities
separate while preserving one lifecycle owner for each service.
