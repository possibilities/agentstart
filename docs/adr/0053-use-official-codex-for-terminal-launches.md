# 0053: Use official Codex for terminal launches

Accepted October 20, 2026. Supersedes the Codex installation and runtime binding
in [ADR 0041](0041-bind-harness-shims-to-owned-forks.md).

AgentStart installs Codex only through its existing official installer. The
permission shim binds the official stable launcher at `~/.local/bin/codex`,
checks that it is executable and is not the shim itself, and never searches
PATH for a replacement. A missing installation fails before shim publication.
The launcher remains stable across the vendor's versioned package updates.

The fork release pin, workshop installer call and workshop lookup are removed.
Official native controls already support the terminal Role delivery. Carrying
an additional fork installation therefore adds maintenance without a remaining
consumer requirement. Stack continues to own its separately pinned complete
official package; the terminal shim does not depend on Stack's installation.
Fx keeps its existing workshop contract and reviewed Integration pin.

Permission defaults, explicit overrides, utility pass-through, native accounts
and histories keep their existing behavior. Convergence changes future launches;
it does not restart an active Codex process, remove the old fork executable,
or delete its workshop or data. Existing owned shims are replaced through the
normal ownership-checked installer.

Evidence: `scripts/install.sh`, `scripts/install-harness-shims`, and the
installed-shim boundary test in `tests/codex-invocation.test.ts`. The fixture
has an official launcher and no Codex workshop, a hostile PATH alternative,
and verifies that a missing native executable fails without fallback.
