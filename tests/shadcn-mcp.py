#!/usr/bin/env python3
"""Live regression check; requires npm and registry access (or a warm cache).

Run separately from the offline validation suite: python3 tests/shadcn-mcp.py.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="shadcn conflicting project ") as directory:
    project = Path(directory).resolve()
    resources = project / "fleet-resources"
    shutil.copytree(root / "config/resources/shadcn", resources / "shadcn")
    (project / "package.json").write_text(json.dumps({
        "name": "mcp-conflict-fixture",
        "dependencies": {"@opentui/core": "0.5.10"},
        "overrides": {"@opentui/core": "0.5.9"},
    }))
    # An invalid project-local shadcn config proves the server uses the fixed
    # fleet registry directory rather than its caller's cwd.
    (project / "components.json").write_text("{}\n")
    requests = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2024-11-05", "capabilities": {},
        "clientInfo": {"name": "agentstart-regression", "version": "1"},
    }}, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
            "name": "get_project_registries", "arguments": {},
        }}]
    env = dict(os.environ, AGENTSTART_RESOURCES_ROOT=str(resources))
    result = subprocess.run(
        [str(root / "scripts/agentstart"), "mcp", "shadcn"], cwd=project,
        env=env, input="".join(json.dumps(request) + "\n" for request in requests),
        capture_output=True, text=True, timeout=45, check=True,
    )
    responses = [json.loads(line) for line in result.stdout.splitlines()]
    assert responses[0]["result"]["serverInfo"]["name"] == "shadcn", responses
    assert responses[1]["id"] == 2, responses
    assert "@shadcn" in responses[1]["result"]["content"][0]["text"], responses
    assert not result.stderr, result.stderr
print("fleet shadcn MCP ignores caller project state and serves its registry")
