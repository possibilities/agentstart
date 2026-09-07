#!/usr/bin/env python3
"""Live regression check; requires npm and registry access (or a warm cache).

Run separately from the offline validation suite: python3 tests/shadcn-mcp.py.
"""

import json
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parent.parent
server = json.loads((root / "config/resources/mcp-servers.json").read_text())[
    "mcpServers"
]["shadcn"]
command = [server["command"], *server["args"]]
with tempfile.TemporaryDirectory(prefix="shadcn conflicting project ") as directory:
    project = Path(directory).resolve()
    (project / "package.json").write_text(json.dumps({
        "name": "mcp-conflict-fixture",
        "dependencies": {"@opentui/core": "0.5.10"},
        "overrides": {"@opentui/core": "0.5.9"},
    }))
    # Commander prints the actual default cwd, catching an accidental chdir
    # to the isolated npm prefix even if initialization itself still succeeds.
    help_result = subprocess.run(
        [*command, "--help"], cwd=project, capture_output=True, text=True,
        timeout=45, check=True,
    )
    assert str(project) in help_result.stdout, help_result.stdout
    request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2024-11-05", "capabilities": {},
        "clientInfo": {"name": "agentstart-regression", "version": "1"},
    }}
    result = subprocess.run(
        command, cwd=project, input=json.dumps(request) + "\n",
        capture_output=True, text=True, timeout=45, check=True,
    )
    response = json.loads(result.stdout)
    assert response["id"] == 1, response
    assert response["result"]["serverInfo"]["name"] == "shadcn", response
    assert not result.stderr, result.stderr
print("shadcn MCP initializes despite project overrides and preserves project cwd")
