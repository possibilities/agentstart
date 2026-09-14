# 0015: Close scoped Work with explicit delivery

Accepted September 14, 2026. Refines [manager-owned recording](0013-managers-own-hud-recording.md).

The human requires managers to drive closure and communicate delivery, but rejects
a universal requirement for human acknowledgment of every completed implementation.
The actual Work scope decides whether landing, installation, production use or
human validation is required. Achieved implementation Work can close; the manager
tells the human what was delivered and is closing rather than silently dropping it.

Technical acceptance, presentation and a genuine human dependency remain distinct.
A tracked answer not acknowledged as heard stays visible, and required approval,
validation or a decision remains unresolved with the exact next human action.
A clear natural response suffices; no special approval word is required. Silence
and mere presentation do not settle an actual dependency. Follow-up is contextual,
respects conversation hold and unrelated topics, and creates no scheduler or
unrequested recurring reminder. Deferred delivery remains pending presentation.

AgentHUD already supports accepted results, presentation histories, Work waiting
state, next action and Attention references. This is a manager procedure using
those facts, not a schema migration or an acknowledgment field. Workers retain
their existing result-return responsibility. No role inventory or live session
state changes. Resource sync prepares future loads; loaded prompts and MCP guide
objects may remain older until the corresponding authorized future reload.

Evidence: manager APPEND prompt, shared GUIDELINES, roles README and AgentHUD's
owned skill/CLI guide/protocol. Validation uses role/resource rendering, native
mode length checks and installed-output inspection, without service restarts.
