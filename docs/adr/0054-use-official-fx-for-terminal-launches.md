# 0054: Use official Fx for terminal launches

Accepted October 20, 2026. Supersedes the Fx installation and runtime binding
in [ADR 0041](0041-bind-harness-shims-to-owned-forks.md).

AgentStart installs Fx through the vendor's `https://fx.sh/setup.sh` into its
default `~/.local/bin/fx` location. The owned shim binds that path, verifies it
is executable and not the shim itself, and passes every argument unchanged.
Missing native installations fail before shim publication and never fall back
to another executable on PATH. Codex follows the equivalent official-path
contract in [ADR 0053](0053-use-official-codex-for-terminal-launches.md).

The Fx Integration pin, Workshop installer call and binary lookup are removed.
AgentStart no longer controls Fx's native upgrade policy. The operator retired
the fork dependency; ordinary convergence must not restore it. The one-time
cutover removes the fork installer's forced `auto_upgrade: false` setting,
preserving other settings and the old source, receipts and history.

Official Fx 0.0.14 rejects the per-invocation Role flags previously used by
AgentRoles. AgentRoles retires that delivery target under its ADR 0010 rather
than continuing to depend on the fork or changing global Fx configuration.
Bare Fx remains available; other supported Role harnesses retain their behavior.

The vendor installer replaces the native executable for future launches.
Convergence does not restart running sessions or remove the Workshop. Embedded
palette constants and historical design attribution in other projects are
independent of the Fx executable and remain intact.

Evidence: the official installer and disposable-profile CLI flag probes,
`scripts/install.sh`, `scripts/install-harness-shims`, the installed-shim
boundary test in `tests/codex-invocation.test.ts`, and `tests/validate.sh`.
