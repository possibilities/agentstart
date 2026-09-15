# 0018: Set the AgentVoice default to Sol/high

Accepted September 15, 2026. The operator requested that AgentVoice use Sol
rather than Astra while retaining high reasoning effort.

Set AgentStart's tracked AgentVoice orchestrator default to `gpt-5.6-sol` with
high reasoning effort. Explicit CLI and captured workspace-role settings retain
their existing precedence. Manager and worker role prompts, resources, and
delegation routing policy are unchanged.

Converge the tracked link through AgentStart's supported nonrestarting
installation path. Existing calls and captured workspace role snapshots keep
their loaded settings until an authorized later load or runtime replacement;
this decision does not restart either one.
