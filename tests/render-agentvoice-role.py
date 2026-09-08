#!/usr/bin/env python3
"""Role composition stays within fixed resources and native role files."""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RENDER = ROOT / "scripts/render-agentvoice-role"


class VoiceRoleRender(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.resources = self.root / "resources"
        skill = self.resources / "skills" / "board"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("---\nname: board\ndescription: fixture\n---\n")
        (self.resources / "mcp-servers.json").write_text(json.dumps({
            "mcpServers": {"executor": {"command": "/fixture/executor", "args": ["mcp"]}}
        }))
        self.source = self.root / "source" / "default"
        self.source.mkdir(parents=True)
        self.prompt = self.source / "APPEND_SYSTEM_PROMPT.md"
        self.prompt.write_text("Keep the app's exact prompt.\n")
        self.role = self.resources / "agentvoice" / "default"

    def render(self, expected=0):
        result = subprocess.run([str(RENDER), str(self.resources), str(self.source)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)

    def test_standard_role_links_resources_and_preserves_prompt(self):
        self.render()
        self.assertEqual((self.role / "APPEND_SYSTEM_PROMPT.md").read_bytes(), self.prompt.read_bytes())
        self.assertEqual(os.readlink(self.role / "skills"), "../../skills")
        self.assertEqual(os.readlink(self.role / "mcp.json"), "../../mcp-servers.json")
        self.assertTrue((self.role / "skills" / "board" / "SKILL.md").is_file())
        self.assertEqual((self.role / "mcp.json").read_bytes(), (self.resources / "mcp-servers.json").read_bytes())

    def test_repeat_is_inert_and_later_prompt_edits_keep_one_source(self):
        self.render()
        inode = self.role.stat().st_ino
        self.render()
        self.assertEqual(self.role.stat().st_ino, inode)
        self.prompt.write_text("Updated app-owned prompt\n")
        self.render()
        self.assertEqual((self.role / "APPEND_SYSTEM_PROMPT.md").read_text(), "Updated app-owned prompt\n")
        self.assertEqual(self.role.stat().st_ino, inode)

    def test_adding_a_native_voice_prompt_preserves_unrelated_roles(self):
        self.render()
        other = self.resources / "agentvoice" / "researcher"
        other.mkdir()
        (other / "APPEND_SYSTEM_PROMPT.md").write_text("Independent role")
        (self.source / "VOICE_AGENT_APPEND_SYSTEM_PROMPT.md").write_text("Voice detail")
        self.render()
        self.assertEqual((self.role / "VOICE_AGENT_APPEND_SYSTEM_PROMPT.md").read_text(), "Voice detail")
        self.assertEqual((other / "APPEND_SYSTEM_PROMPT.md").read_text(), "Independent role")

    def test_independent_destination_or_changed_link_is_preserved(self):
        self.role.mkdir(parents=True)
        (self.role / "note.md").write_text("Independent")
        self.render(1)
        self.assertEqual((self.role / "note.md").read_text(), "Independent")
        (self.role / "note.md").unlink()
        self.role.rmdir()
        self.render()
        (self.role / "skills").unlink()
        (self.role / "skills").symlink_to(self.root / "other")
        self.render(1)
        self.assertEqual(os.readlink(self.role / "skills"), str(self.root / "other"))

    def test_source_resource_conflict_keeps_the_existing_role(self):
        self.render()
        receipt = (self.role / ".agentstart-role.json").read_bytes()
        (self.source / "mcp.json").write_text('{"mcpServers":{}}')
        self.render(1)
        self.assertEqual((self.role / ".agentstart-role.json").read_bytes(), receipt)

    def test_effective_prompt_conflict_is_rejected_before_publication(self):
        (self.source / "VOICE_ORCHESTRATOR_SYSTEM_PROMPT.md").write_text("Conflicts with general append")
        self.render(1)
        self.assertFalse(self.role.exists())

    def test_redirected_role_parent_is_preserved(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.resources / "agentvoice").symlink_to(outside)
        self.render(1)
        self.assertEqual(list(outside.iterdir()), [])

    def test_missing_optional_app_source_is_a_skip(self):
        self.prompt.unlink()
        self.source.rmdir()
        self.render()
        self.assertFalse(self.role.exists())


if __name__ == "__main__":
    unittest.main()
