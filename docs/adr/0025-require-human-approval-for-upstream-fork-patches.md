# 0025: Require human approval for upstream fork patches

Accepted September 16, 2026. Refines the manager and worker repository authority
boundary without changing ordinary first-party implementation authority.

Creating, maintaining, rebasing or applying a patch carried against an external
upstream requires explicit human approval. The agent detects that decision before
modifying the fork and surfaces the need early with alternatives, the continuing
maintenance burden and a recommended route that avoids carrying a patch when one
is available. Authorization for the surrounding task does not imply this choice.
After approval, the existing workshop `MAINTAIN.md`, integration branch and
consumer procedures remain authoritative.

Before recommending or preparing an upstream issue or pull request, the agent
reads the repository's current contribution, security, template and reporting
guidance and assesses recent repository behavior: maintainer preferences,
accepted contribution patterns, review expectations and communication norms.
The agent prepares a concrete reviewable action, but opening or materially
updating the issue or pull request requires the human's explicit approval for
that action. This covers substantive body, patch-set, comment and reply changes;
read-only investigation does not require approval.

The manager owns the human decision and approval evidence. A delegated worker
returns the candidate action and evidence to its parent unless direct human
coordination was assigned. Ordinary authorized implementation in a first-party
repository continues under the task and repository instructions without this
additional gate. Role rendering and installation prepare future launches; they
do not alter loaded snapshots or restart AgentVoice.

Evidence: default-role APPEND prompt, shared GUIDELINES, roles README,
render contract tests and installed-role freshness checks.
