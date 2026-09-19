# 0035: Use the maximum AgentVoice context window

Accepted September 19, 2026. The operator requested the larger Codex context
window for AgentVoice's AgentStart-owned manager default.

Set `orchestrator.config.model_context_window` to `872000` in AgentStart's
tracked AgentVoice `server.json`. The current native model catalog advertises
that maximum for both `gpt-5.6-sol` and `gpt-6-astra`; Codex remains the
authority that validates and clamps the value for the selected model. Keep the
setting thread-local through AgentVoice's native `config` request rather than
changing the operator's global Codex preferences.

The existing model and reasoning defaults remain Sol/high. Explicit CLI and
captured workspace-role settings retain their established precedence. Install
the tracked configuration through AgentStart's supported convergence path; do
not restart an active AgentVoice runtime as part of installation. The larger
window applies after the next separately authorized runtime replacement.
