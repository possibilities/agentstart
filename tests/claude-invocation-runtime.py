#!/usr/bin/env python3
"""Opt-in stock-Claude PTY proof. No real account or reachable API provider."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import time
import uuid


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=40, **kwargs).stdout


def main():
    native = Path(os.environ.get("CLAUDE_NATIVE_BIN") or Path.home() / ".local/bin/claude").resolve()
    helper = Path(__file__).resolve().parents[1] / "scripts/claude-invocation"
    termctrl = shutil.which("termctrl")
    assert termctrl and native.is_file(), "native Claude and termctrl are required"
    with tempfile.TemporaryDirectory(prefix="claude-native-proof-") as directory:
        root = Path(directory).resolve()
        config = root / "config"
        config.mkdir()
        repo = root / "repo"
        repo.mkdir()
        run("git", "init", cwd=repo)
        run("git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-m", "fixture", cwd=repo)
        worktree = root / "worktree"
        run("git", "worktree", "add", "--detach", str(worktree), cwd=repo)
        cwd = worktree / "subdir"
        cwd.mkdir()
        marker = root / "trusted-project-hook-ran"
        (cwd / ".claude").mkdir()
        (cwd / ".claude/settings.json").write_text(json.dumps({"hooks": {"SessionStart": [{"matcher": "*", "hooks": [{"type": "command", "command": "touch " + shlex.quote(str(marker))}]}]}}))
        (config / ".claude.json").write_text(json.dumps({"hasCompletedOnboarding": True, "theme": "dark", "customApiKeyResponses": {"approved": ["sk-ant-test"]}, "fixture": "preserve"}))
        source = root / "authored.json"
        source.write_text(json.dumps({"model": "sonnet", "permissions": {"defaultMode": "manual"}, "spinnerTipsEnabled": False}))
        (config / "preferences.json").symlink_to(source)
        source_bytes = source.read_bytes()
        environment = ["/usr/bin/env", "-u", "CLAUDECODE", "-u", "CLAUDE_CODE_SANDBOXED", "-u", "CLAUDE_CODE_SESSION_KIND",
                       f"HOME={root}", f"CLAUDE_CONFIG_DIR={config}", "ANTHROPIC_API_KEY=sk-ant-test", "ANTHROPIC_BASE_URL=http://127.0.0.1:1",
                       "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1", f"AGENTSTART_CLAUDE_CONFIG_SOURCE={config / 'preferences.json'}", "AGENTSTART_CLAUDE_TRUST=1"]
        for wrapped in (False, True):
            name = "claude-trust-proof-" + uuid.uuid4().hex[:10]
            args = [str(helper), str(native)] if wrapped else [str(native), "--settings", str(source)]
            args += ["--debug-file", str(root / "debug.log")]
            try:
                run(termctrl, "start", name, "--cols", "100", "--rows", "30", "--", *environment, *args, cwd=cwd)
                expected = "manual mode on" if wrapped else "Quick safety check"
                run(termctrl, "wait", name, expected, "--timeout", "20000")
                screen = run(termctrl, "show", name)
                assert expected in screen, screen
                if wrapped:
                    assert "Sonnet" in screen and "Quick safety check" not in screen, screen
                    deadline = time.monotonic() + 5
                    while not marker.exists() and time.monotonic() < deadline:
                        time.sleep(0.05)
                    if not marker.exists():
                        debug = (root / "debug.log").read_text()
                        relevant = [line for line in debug.splitlines() if any(word in line.lower() for word in ("hook", "settings", "trust"))]
                        raise AssertionError("trusted project SessionStart hook did not run\n" + "\n".join(relevant[-30:]))
                else:
                    assert not marker.exists(), "project hook ran before trust"
            finally:
                subprocess.run([termctrl, "stop", name], capture_output=True, timeout=15)
        state = json.loads((config / ".claude.json").read_text())
        assert state["fixture"] == "preserve"
        for path in (cwd, worktree, repo):
            assert state["projects"][str(path)]["hasTrustDialogAccepted"] is True
        assert source.read_bytes() == source_bytes
        assert (config / "preferences.json").is_symlink()
        print("Native Claude proof passed: trust dialog before, normal manual-mode prompt after; authored model, trusted project hook, worktree roots, and Stow link verified.")


if __name__ == "__main__":
    main()
