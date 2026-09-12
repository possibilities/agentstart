#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts" / "install-herdr-codex-session-fallback"


def run_installer(codex_home: Path, mode: str = "--install", check: bool = True):
    env = {**os.environ, "CODEX_HOME": str(codex_home)}
    return subprocess.run([INSTALLER, mode], env=env, text=True, capture_output=True, check=check)


def run_hook(codex_home: Path, fake_herdr: Path, payload: dict, **overrides: str):
    env = {
        **os.environ,
        "CODEX_HOME": str(codex_home),
        "AGENTLAUNCH_LAUNCH": "1",
        "HERDR_ENV": "1",
        "HERDR_SOCKET_PATH": str(codex_home / "herdr.sock"),
        "HERDR_PANE_ID": "wTEST:p1",
        "CODEX_THREAD_ID": "thread-test",
        "HERDR_BIN_PATH": str(fake_herdr),
        **overrides,
    }
    return subprocess.run(
        [codex_home / "herdr-agent-session-fallback.sh"],
        env=env,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=True,
    )


with tempfile.TemporaryDirectory(prefix="agentstart-herdr-codex-test.") as directory:
    root = Path(directory)
    codex_home = root / "codex"
    codex_home.mkdir()
    hooks_file = codex_home / "hooks.json"
    hooks_file.write_text(
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {"hooks": [{"type": "command", "command": "touch unrelated"}]}
                    ]
                }
            }
        )
        + "\n"
    )
    legacy = codex_home / "herdr-agent-session-fallback.sh"
    legacy.write_text("#!/bin/sh\n# Temporary local fallback for Herdr Codex integration v8.\n")

    run_installer(codex_home)
    installed = legacy.read_text()
    assert "# AGENTSTART_MANAGED_CODEX_HERDR_SESSION_FALLBACK=1" in installed
    document = json.loads(hooks_file.read_text())
    groups = document["hooks"]["SessionStart"]
    handlers = [handler for group in groups for handler in group.get("hooks", [])]
    expected_command = f"bash '{legacy}'"
    assert {"command": "touch unrelated", "type": "command"} in handlers
    assert handlers.count({"command": expected_command, "timeout": 10, "type": "command"}) == 1

    before = (legacy.read_bytes(), hooks_file.read_bytes())
    run_installer(codex_home)
    assert before == (legacy.read_bytes(), hooks_file.read_bytes())

    (codex_home / "herdr-agent-state.sh").write_text("# HERDR_INTEGRATION_VERSION=8\n")
    capture = root / "herdr-argv.json"
    fake_herdr = root / "herdr"
    fake_herdr.write_text(
        "#!/bin/bash\n"
        "python3 -c 'import json,os,sys; "
        "open(os.environ[\"HERDR_CAPTURE\"],\"w\").write(json.dumps(sys.argv[1:]))' \"$@\"\n"
    )
    fake_herdr.chmod(0o755)
    payload = {
        "hook_event_name": "SessionStart",
        "session_id": "thread-test",
        "transcript_path": None,
        "source": "startup",
    }
    run_hook(codex_home, fake_herdr, payload, HERDR_CAPTURE=str(capture))
    argv = json.loads(capture.read_text())
    assert argv[:4] == ["pane", "report-agent-session", "wTEST:p1", "--source"]
    assert argv[4:8] == ["herdr:codex", "--agent", "codex", "--seq"]
    assert argv[-4:] == ["--agent-session-id", "thread-test", "--session-start-source", "startup"]

    for environment, changed_payload in [
        ({"AGENTLAUNCH_LAUNCH": ""}, payload),
        ({"HERDR_ENV": ""}, payload),
        ({"CODEX_THREAD_ID": "another-thread"}, payload),
        ({}, {**payload, "transcript_path": "/a/resumed/transcript.jsonl"}),
    ]:
        capture.unlink(missing_ok=True)
        run_hook(
            codex_home,
            fake_herdr,
            changed_payload,
            HERDR_CAPTURE=str(capture),
            **environment,
        )
        assert not capture.exists(), (environment, changed_payload)

    (codex_home / "herdr-agent-state.sh").write_text("# HERDR_INTEGRATION_VERSION=9\n")
    capture.unlink(missing_ok=True)
    run_hook(codex_home, fake_herdr, payload, HERDR_CAPTURE=str(capture))
    assert not capture.exists()

    run_installer(codex_home, "--uninstall")
    assert not legacy.exists()
    remaining = json.loads(hooks_file.read_text())
    assert remaining == {
        "hooks": {
            "SessionStart": [
                {"hooks": [{"type": "command", "command": "touch unrelated"}]}
            ]
        }
    }

    foreign_home = root / "foreign"
    foreign_home.mkdir()
    (foreign_home / "herdr-agent-session-fallback.sh").write_text("#!/bin/sh\necho foreign\n")
    refused = run_installer(foreign_home, check=False)
    assert refused.returncode != 0
    assert "refusing to replace an unowned fallback target" in refused.stderr

print("codex Herdr session fallback tests passed")
