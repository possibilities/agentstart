#!/usr/bin/env python3
"""Verify default-role rendering, attestation, and safe old-role retirement."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RoleRender(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.resources = self.root / "resources"
        (self.resources / "skills" / "example").mkdir(parents=True)
        (self.resources / "skills" / "example" / "SKILL.md").write_text("fixture")
        self.sources = self.root / "sources"
        source = self.sources / "default"
        source.mkdir(parents=True)
        (source / "APPEND_SYSTEM_PROMPT.md").write_text("default")
        (source / "mcp.json").write_text(json.dumps({"mcpServers": {
            "example": {"command": "${HOME}/.local/bin/example", "args": ["mcp"]}}}))

    def render(self, expected=0, sources=None):
        result = subprocess.run([
            "python3", str(ROOT / "scripts/render-roles"),
            str(self.resources), str(sources or self.sources),
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def copy_default_to(self, name):
        source = self.resources / "roles/default"
        shutil.copytree(source, self.resources / "roles" / name, symlinks=True)

    def test_default_expands_home_owns_prompt_and_is_rerunnable(self):
        self.render()
        role = self.resources / "roles/default"
        self.assertEqual((role / "APPEND_SYSTEM_PROMPT.md").resolve(),
                         (self.sources / "default/APPEND_SYSTEM_PROMPT.md").resolve())
        self.assertTrue((role / "skills/example/SKILL.md").is_file())
        self.assertEqual(json.loads((role / "mcp.json").read_text()), {"mcpServers": {
            "example": {"command": str(Path.home() / ".local/bin/example"),
                        "args": ["mcp"]}}})
        self.assertEqual((role / "mcp.json").stat().st_mode & 0o777, 0o600)
        inode = role.stat().st_ino
        self.render()
        self.assertEqual(role.stat().st_ino, inode)
        source = self.sources / "default/mcp.json"
        source.write_text(source.read_text().replace('"mcp"', '"different"'))
        self.render()
        self.assertNotEqual(role.stat().st_ino, inode)
        self.assertEqual(json.loads((role / "mcp.json").read_text())
                         ["mcpServers"]["example"]["args"], ["different"])

    def test_invalid_source_does_not_publish(self):
        (self.sources / "default/mcp.json").write_text('{"mcpServers":{"bad.name":{}}}')
        self.render(1)
        self.assertFalse((self.resources / "roles/default").exists())

    def test_changed_destination_is_preserved(self):
        self.render()
        mcp = self.resources / "roles/default/mcp.json"
        mcp.write_text("independent change")
        self.render(1)
        self.assertEqual(mcp.read_text(), "independent change")

    def test_receipt_tracks_resolved_prompt_and_skill_content(self):
        self.render()
        role = self.resources / "roles/default"
        receipt = json.loads((role / ".agentstart-role.json").read_text())
        self.assertEqual(receipt["owner"], "agentstart-role-v4")
        self.assertEqual(receipt["content"]["format"], "agentvoice-role-content-v1")
        for component in ("content", "prompts", "mcp", "skills"):
            self.assertRegex(receipt["content"][component], r"^[a-f0-9]{64}$")

        old_prompt = receipt["content"]["prompts"]
        old_skills = receipt["content"]["skills"]
        (self.sources / "default/APPEND_SYSTEM_PROMPT.md").write_text("changed")
        self.render()
        receipt = json.loads((role / ".agentstart-role.json").read_text())
        self.assertNotEqual(receipt["content"]["prompts"], old_prompt)
        self.assertEqual(receipt["content"]["skills"], old_skills)

        (self.resources / "skills/example/SKILL.md").write_text("fixture changed")
        self.render()
        self.assertNotEqual(
            json.loads((role / ".agentstart-role.json").read_text())["content"]["skills"],
            old_skills,
        )

    def test_owned_manager_and_worker_are_retired_after_default_publish(self):
        self.render()
        self.copy_default_to("manager")
        self.copy_default_to("worker")
        (self.resources / "roles/default").rename(self.root / "old-default")
        result = self.render()
        self.assertIn("Rendered default role", result.stdout)
        self.assertIn("Removed retired manager role", result.stdout)
        self.assertIn("Removed retired worker role", result.stdout)
        self.assertTrue((self.resources / "roles/default").is_dir())
        self.assertFalse((self.resources / "roles/manager").exists())
        self.assertFalse((self.resources / "roles/worker").exists())

    def test_retired_roles_are_removed_without_replacing_fresh_default(self):
        self.render()
        role = self.resources / "roles/default"
        inode = role.stat().st_ino
        self.copy_default_to("manager")
        self.copy_default_to("worker")
        self.render()
        self.assertEqual(role.stat().st_ino, inode)
        self.assertFalse((self.resources / "roles/manager").exists())
        self.assertFalse((self.resources / "roles/worker").exists())

    def test_independent_retired_role_blocks_cutover(self):
        parent = self.resources / "roles"
        (parent / "worker").mkdir(parents=True)
        (parent / "worker/note").write_text("independent")
        self.render(1)
        self.assertFalse((parent / "default").exists())
        self.assertEqual((parent / "worker/note").read_text(), "independent")

    def test_tampered_retired_role_blocks_default_update(self):
        self.render()
        role = self.resources / "roles/default"
        before = (role / "mcp.json").read_bytes()
        self.copy_default_to("worker")
        retired = self.resources / "roles/worker/mcp.json"
        retired.write_text("preserve me")
        source = self.sources / "default/mcp.json"
        source.write_text(source.read_text().replace('"mcp"', '"different"'))
        self.render(1)
        self.assertEqual((role / "mcp.json").read_bytes(), before)
        self.assertEqual(retired.read_text(), "preserve me")

    def test_redirected_parent_is_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.resources / "roles").symlink_to(outside)
        self.render(1)
        self.assertEqual(list(outside.iterdir()), [])

    def test_missing_and_conflicting_prompts_fail(self):
        prompt = self.sources / "default/APPEND_SYSTEM_PROMPT.md"
        prompt.unlink()
        self.render(1)
        prompt.write_text("default")
        (self.sources / "default/VOICE_ORCHESTRATOR_SYSTEM_PROMPT.md").write_text("conflict")
        self.render(1)

    def test_shipped_default_mcp_is_attested_and_strict(self):
        self.render(sources=ROOT / "roles")
        source = json.loads((ROOT / "roles/default/mcp.json").read_text())
        role = self.resources / "roles/default"
        mcp_bytes = (role / "mcp.json").read_bytes()
        rendered = json.loads(mcp_bytes)
        receipt = json.loads((role / ".agentstart-role.json").read_text())

        servers = rendered["mcpServers"]
        self.assertEqual(set(servers), set(source["mcpServers"]))
        self.assertTrue(servers)
        self.assertTrue({
            "agentattention", "agentchats", "agentfx", "agentgrok",
            "agenthud", "agentkeys", "agentmux", "agentsounds", "agentsurface",
        }.isdisjoint(name.lower() for name in servers))
        for server in servers.values():
            self.assertEqual(set(server), {"command", "args"})
            command = server["command"]
            self.assertTrue(Path(command).is_absolute() or
                            re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}", command))
            self.assertIsInstance(server["args"], list)
            self.assertTrue(all(isinstance(argument, str) for argument in server["args"]))

        mcp_sha256 = hashlib.sha256(mcp_bytes).hexdigest()
        framed = json.dumps([
            "agentvoice-role-content-v1",
            [{"path": "mcp.json", "kind": "file", "hash": mcp_sha256}],
        ], separators=(",", ":")).encode()
        self.assertEqual(receipt["mcp_sha256"], mcp_sha256)
        self.assertEqual(receipt["content"]["mcp"], hashlib.sha256(framed).hexdigest())
        self.assertEqual((role / "mcp.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual((role / ".agentstart-role.json").stat().st_mode & 0o777, 0o600)

    def test_shipped_default_is_complete_and_mode_fits_native_limit(self):
        (self.resources / "skills/hud").mkdir()
        (self.resources / "skills/hud/SKILL.md").write_text("default role")
        self.render(sources=ROOT / "roles")
        source = ROOT / "roles/default"
        role = self.resources / "roles/default"
        for filename in (
            "APPEND_SYSTEM_PROMPT.md", "VOICE_AGENT_APPEND_SYSTEM_PROMPT.md",
            "VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md",
        ):
            self.assertEqual((role / filename).read_bytes(), (source / filename).read_bytes())
        self.assertLessEqual(len((role / "VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md").read_bytes()),
                             1600)
        self.assertTrue((role / "skills/hud/SKILL.md").is_file())

        prompt = (role / "APPEND_SYSTEM_PROMPT.md").read_text()
        for expected in (
            "AgentHUD stores no Resource or Lease records",
            "When the human asks for a sketch",
            "Default toward speculative durable tracking",
            "Never create or dispatch a worker",
            "Every substantive worker brief",
            "Detect an external/upstream fork-patch decision before modifying the fork",
        ):
            self.assertIn(expected, prompt)
        for retired in (
            "reconcile its HUD resource and lease records",
            "actively compare the live native Codex option with AgentFX targets",
            "routing_source_revision",
            "agentfx-stage-1-shadow",
        ):
            self.assertNotIn(retired, prompt)

        guidance = "\n".join(path.read_text() for path in role.glob("*.md"))
        self.assertIn("agentvoice.subagent_completion", guidance)
        self.assertIn("immediate native parent", guidance)
        for retired in (
            "agentvoice_thread_mailbox_open", "agentvoice.thread_mailbox_notice",
            "remainingCompleted", "expectedInstanceId",
        ):
            self.assertNotIn(retired, guidance)


if __name__ == "__main__":
    unittest.main()
