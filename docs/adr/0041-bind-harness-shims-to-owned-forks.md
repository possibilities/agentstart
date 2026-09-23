# 0041: Bind harness shims to owned forks

Accepted September 23, 2026.

AgentStart installs Fx through fxnk's existing exact Integration source-build
contract and Codex through codexnk's stable release installer with an exact tag
and Integration SHA. The workshops own binary layout, verification, receipts,
and atomic publication. AgentStart owns the reviewed consumer pins and ordering.
The Codex fork lives under `~/.local/libexec/codexnk`, leaving vendor Codex intact.

Both workshop installers expose read-only `--print-bin`. AgentStart's shim
installer requires these absolute executable paths and embeds them in its
owned shims. Missing workshops or binaries fail; another PATH executable is
not a fallback. Claude still resolves its official binary through PATH.
Codex retains the existing permission defaults and utility pass-through; Fx
passes every argument unchanged. No identity, capabilities, role, model, or
history selection is added. Permission bypass does not select the vendor binary.

This changes only future processes. Convergence must not restart active calls
or applications. Unattended skill sync does not update binaries or uninstall
plugins. Explicit role publication still includes both Codex and Devin.

Evidence: `scripts/install.sh`, `scripts/install-harness-shims`,
`tests/validate.sh`, `tests/harness-config.test.ts`, and the workshop installers.
