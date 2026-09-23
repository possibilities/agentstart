# 0017: Attest role content and audit Codex copies

The two-copy role surface is superseded September 23, 2026 by
[ADR 0040](0040-collapse-explicit-roles-to-default.md). Content attestation and
read-only Codex freshness checks remain current for the single `default` role.

Date: 2026-09-14

## Status

Accepted

## Decision

Rendered manager and worker ownership receipts record content-only digests of
the resolved prompt, rendered MCP, and resolved skill inputs. The digest uses
AgentVoice's `agentvoice-role-content-v1` framing so publication and runtime
status can name the same bytes without retaining prompt bodies, MCP values, or
symlink target paths.

`scripts/sync-skills --check` invokes AgentRoles' read-only
`install --check` operation for both already-rendered roles. A stale installed
Codex skill copy fails the check and reports only missing, extra, and changed
relative paths. A bootstrap machine without rendered roles or a supporting
AgentRoles version keeps the installation plan available.

Actual Codex plugin refresh remains the explicit
`agentroles install <rendered-role>` operation. Normal resource convergence does
not write Codex plugin state, reload AgentVoice, or migrate workspace roles.

## Consequences

Prompt and skill changes now replace AgentStart's owned rendered role directory
and update its receipt even though those assets are symlink-backed. The receipt
is publication evidence; AgentVoice still observes the bytes loaded by each
runtime generation and computes current desired state independently.

Existing version 2 and version 3 ownership receipts remain safely recognized
and migrate on the next render. Database-backed AgentVoice workspaces keep their
revision contract and do not consume this directory receipt.
