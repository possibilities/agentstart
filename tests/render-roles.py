#!/usr/bin/env python3
"""Verify independent role inventories and ownership-safe convergence."""
import json
import os
from pathlib import Path
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
        for name in ("manager", "worker"):
            source = self.sources / name
            source.mkdir(parents=True)
            (source / "APPEND_SYSTEM_PROMPT.md").write_text(name)
            (source / "mcp.json").write_text(json.dumps({"mcpServers": {
                name: {"command": "${HOME}/.local/bin/example", "args": ["mcp"]}}}))

    def render(self, expected=0, sources=None):
        result = subprocess.run(["python3", str(ROOT / "scripts/render-roles"),
                                 str(self.resources), str(sources or self.sources)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)

    def test_separate_rosters_expand_home_and_keep_prompt_ownership(self):
        self.render()
        for name in ("manager", "worker"):
            role = self.resources / "roles" / name
            self.assertEqual((role / "APPEND_SYSTEM_PROMPT.md").resolve(),
                             self.sources / name / "APPEND_SYSTEM_PROMPT.md")
            self.assertTrue((role / "skills/example/SKILL.md").is_file())
            self.assertEqual(json.loads((role / "mcp.json").read_text()), {"mcpServers": {
                name: {"command": str(Path.home() / ".local/bin/example"), "args": ["mcp"]}}})
            self.assertEqual((role / "mcp.json").stat().st_mode & 0o777, 0o600)
        worker = self.resources / "roles/worker"
        inode = worker.stat().st_ino
        self.render()
        self.assertEqual(worker.stat().st_ino, inode)
        source = self.sources / "manager/mcp.json"
        source.write_text(source.read_text().replace('"mcp"', '"different"'))
        self.render()
        self.assertEqual(worker.stat().st_ino, inode)
        self.assertEqual(json.loads((self.resources / "roles/manager/mcp.json").read_text())
                         ["mcpServers"]["manager"]["args"], ["different"])

    def test_invalid_second_source_does_not_publish_first(self):
        (self.sources / "worker/mcp.json").write_text('{"mcpServers":{"bad.name":{}}}')
        self.render(1)
        self.assertFalse((self.resources / "roles/manager").exists())

    def test_changed_mcp_is_preserved(self):
        self.render()
        mcp = self.resources / "roles/worker/mcp.json"
        mcp.write_text("independent change")
        self.render(1)
        self.assertEqual(mcp.read_text(), "independent change")

    def test_independent_destination_and_redirect_are_preserved(self):
        parent = self.resources / "roles"
        parent.mkdir()
        (parent / "worker").mkdir()
        (parent / "worker/note").write_text("independent")
        self.render(1)
        self.assertFalse((parent / "manager").exists())

    def test_redirected_parent_is_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.resources / "roles").symlink_to(outside)
        self.render(1)
        self.assertEqual(list(outside.iterdir()), [])

    def test_missing_source_and_conflicting_prompts_fail(self):
        (self.sources / "worker/APPEND_SYSTEM_PROMPT.md").unlink()
        self.render(1)
        (self.sources / "worker/APPEND_SYSTEM_PROMPT.md").write_text("worker")
        (self.sources / "worker/VOICE_ORCHESTRATOR_SYSTEM_PROMPT.md").write_text("conflict")
        self.render(1)

    def test_filtered_worker_migrates_owned_shared_link_and_tracks_skill_changes(self):
        hud = self.resources / "skills/hud"
        hud.mkdir()
        (hud / "SKILL.md").write_text("manager-only")
        self.render()
        manager = self.resources / "roles/manager"
        worker = self.resources / "roles/worker"
        manager_inode = manager.stat().st_ino
        self.assertTrue((worker / "skills").is_symlink())
        (self.sources / "worker/skills-exclude.json").write_text('["hud"]')
        self.render()
        self.assertEqual(manager.stat().st_ino, manager_inode)
        self.assertFalse((worker / "skills").is_symlink())
        self.assertFalse((worker / "skills/hud").exists())
        self.assertTrue((manager / "skills/hud/SKILL.md").is_file())
        self.assertEqual((worker / "skills/example/SKILL.md").read_text(), "fixture")
        worker_inode = worker.stat().st_ino
        self.render()
        self.assertEqual(worker.stat().st_ino, worker_inode)
        extra = self.resources / "skills/new-skill"
        extra.mkdir()
        (extra / "SKILL.md").write_text("new")
        self.render()
        self.assertTrue((worker / "skills/new-skill/SKILL.md").is_file())
        self.assertFalse((worker / "skills/hud").exists())
        (extra / "SKILL.md").unlink()
        extra.rmdir()
        self.render()
        self.assertFalse((worker / "skills/new-skill").exists())

    def test_filtered_skill_tampering_prevents_both_role_updates(self):
        (self.sources / "worker/skills-exclude.json").write_text('["hud"]')
        self.render()
        manager = self.resources / "roles/manager"
        before = (manager / "mcp.json").read_bytes()
        skill = self.resources / "roles/worker/skills/example"
        skill.unlink()
        skill.mkdir()
        (skill / "independent").write_text("preserve")
        source = self.sources / "manager/mcp.json"
        source.write_text(source.read_text().replace('"mcp"', '"different"'))
        self.render(1)
        self.assertEqual((skill / "independent").read_text(), "preserve")
        self.assertEqual((manager / "mcp.json").read_bytes(), before)

    def test_invalid_or_redirected_exclusions_do_not_publish_roles(self):
        path = self.sources / "worker/skills-exclude.json"
        for value in ('{}', '["../hud"]', '["hud", "hud"]', '[null]'):
            path.write_text(value)
            self.render(1)
            self.assertFalse((self.resources / "roles/manager").exists())
        path.unlink()
        elsewhere = self.root / "excluded.json"
        elsewhere.write_text('["hud"]')
        path.symlink_to(elsewhere)
        self.render(1)
        self.assertFalse((self.resources / "roles/manager").exists())

    def test_shipped_roles_are_complete_and_modes_fit_native_limit(self):
        (self.resources / "skills/hud").mkdir()
        (self.resources / "skills/hud/SKILL.md").write_text("manager-only")
        self.render(sources=ROOT / "roles")
        for name in ("manager", "worker"):
            source = ROOT / "roles" / name
            inventory = json.loads((source / "mcp.json").read_text())["mcpServers"]
            self.assertTrue(inventory)
            self.assertEqual("agenthud" in inventory, name == "manager")
            role = self.resources / "roles" / name
            self.assertEqual(set(json.loads((role / "mcp.json").read_text())["mcpServers"]), set(inventory))
            for filename in ("APPEND_SYSTEM_PROMPT.md", "VOICE_AGENT_APPEND_SYSTEM_PROMPT.md",
                             "VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md"):
                self.assertEqual((role / filename).read_bytes(), (source / filename).read_bytes())
            self.assertLessEqual(len((role / "VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md").read_bytes()), 1600)
            self.assertEqual((role / "skills/hud/SKILL.md").exists(), name == "manager")


if __name__ == "__main__":
    unittest.main()
