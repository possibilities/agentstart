# 0024: Deliver AgentVoice child completions directly

Accepted September 16, 2026. Supersedes the AgentVoice mailbox guidance in
[ADR 0012](0012-conversation-hold-guidance.md) without changing that decision's
conversation-hold contract.

An AgentVoice call root receives a terminal direct-child turn through a
`turn/start` payload named `agentvoice.subagent_completion`. The payload carries
the child's terminal metadata and completion content directly, so manager and
worker-root guidance must not advertise a mailbox, an opening tool, paging, or
mailbox recovery.

The root reconciles the payload with any native result by child thread and turn,
treating repeated delivery as duplicate evidence rather than another result. A
later assignment on the same child remains a distinct turn. Terminal content is
evidence for the parent to inspect; it does not establish acceptance, human
presentation, or Work completion.

AgentVoice sends this direct completion only for the root's direct native child.
Native immediate-parent semantics continue below that boundary: a nested child
returns to its parent, which accepts and integrates the result before reporting
upward. The root therefore does not poll for or expect an independent completion
for a grandchild.

AgentStart owns the role prompts and rendered role publication. Its role-render
test rejects the retired mailbox identifiers and checks the direct-completion and
immediate-parent contract in both shipped roles. Resource convergence updates
future role loads; it does not restart AgentVoice or reload an active call.

Evidence: [manager prompt](../../roles/manager/APPEND_SYSTEM_PROMPT.md),
[manager native mode](../../roles/manager/VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md),
[worker native mode](../../roles/worker/VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md),
and [role render test](../../tests/render-roles.py).
