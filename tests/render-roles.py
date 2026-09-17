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
                             (self.sources / name / "APPEND_SYSTEM_PROMPT.md").resolve())
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

    def test_receipt_tracks_resolved_prompt_and_skill_content(self):
        self.render()
        manager = self.resources / "roles/manager"
        worker = self.resources / "roles/worker"
        receipt = json.loads((manager / ".agentstart-role.json").read_text())
        self.assertEqual(receipt["owner"], "agentstart-role-v4")
        self.assertEqual(receipt["content"]["format"], "agentvoice-role-content-v1")
        for component in ("content", "prompts", "mcp", "skills"):
            self.assertRegex(receipt["content"][component], r"^[a-f0-9]{64}$")

        manager_inode = manager.stat().st_ino
        worker_inode = worker.stat().st_ino
        old_content = receipt["content"]
        (self.sources / "manager/APPEND_SYSTEM_PROMPT.md").write_text("manager changed")
        self.render()
        receipt = json.loads((manager / ".agentstart-role.json").read_text())
        self.assertNotEqual(manager.stat().st_ino, manager_inode)
        self.assertEqual(worker.stat().st_ino, worker_inode)
        self.assertNotEqual(receipt["content"]["prompts"], old_content["prompts"])
        self.assertEqual(receipt["content"]["skills"], old_content["skills"])

        manager_inode = manager.stat().st_ino
        worker_inode = worker.stat().st_ino
        manager_skills = receipt["content"]["skills"]
        worker_skills = json.loads((worker / ".agentstart-role.json").read_text())["content"]["skills"]
        (self.resources / "skills/example/SKILL.md").write_text("fixture changed")
        self.render()
        self.assertNotEqual(manager.stat().st_ino, manager_inode)
        self.assertNotEqual(worker.stat().st_ino, worker_inode)
        self.assertNotEqual(
            json.loads((manager / ".agentstart-role.json").read_text())["content"]["skills"],
            manager_skills,
        )
        self.assertNotEqual(
            json.loads((worker / ".agentstart-role.json").read_text())["content"]["skills"],
            worker_skills,
        )

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
            self.assertEqual("agentfx" in inventory, name == "manager")
            if name == "manager":
                self.assertEqual(inventory["agentfx"], {
                    "command": "${HOME}/.local/bin/agentfx",
                    "args": ["mcp", "--config", "${HOME}/.config/agentfx/quota-routing.json"],
                })
            self.assertEqual(inventory["agentmux"], {
                "command": "${HOME}/.local/bin/agentmux",
                "args": ["mcp", "--instance", "default"],
            })
            role = self.resources / "roles" / name
            rendered = json.loads((role / "mcp.json").read_text())["mcpServers"]
            self.assertEqual(set(rendered), set(inventory))
            self.assertEqual(rendered["agentmux"], {
                "command": str(Path.home() / ".local/bin/agentmux"),
                "args": ["mcp", "--instance", "default"],
            })
            if name == "manager":
                self.assertEqual(rendered["agentfx"], {
                    "command": str(Path.home() / ".local/bin/agentfx"),
                    "args": ["mcp", "--config", str(Path.home() / ".config/agentfx/quota-routing.json")],
                })
            for filename in ("APPEND_SYSTEM_PROMPT.md", "VOICE_AGENT_APPEND_SYSTEM_PROMPT.md",
                             "VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md"):
                self.assertEqual((role / filename).read_bytes(), (source / filename).read_bytes())
            self.assertLessEqual(len((role / "VOICE_ORCHESTRATOR_MULTI_AGENT_MODE.md").read_bytes()), 1600)
            self.assertEqual((role / "skills/hud/SKILL.md").exists(), name == "manager")
        self.assertIn("A HUD record is never permission",
                      (self.resources / "roles/manager/APPEND_SYSTEM_PROMPT.md").read_text())
        self.assertIn("When the human asks for a sketch",
                      (self.resources / "roles/manager/APPEND_SYSTEM_PROMPT.md").read_text())
        manager_prompt = (self.resources / "roles/manager/APPEND_SYSTEM_PROMPT.md").read_text()
        worker_prompt = (self.resources / "roles/worker/APPEND_SYSTEM_PROMPT.md").read_text()
        for prompt in (manager_prompt, worker_prompt):
            self.assertIn("Detect an external/upstream fork-patch decision before modifying the fork", prompt)
            self.assertIn("Do not create, maintain, rebase or apply a patch", prompt)
            self.assertIn("ongoing maintenance burden", prompt)
            self.assertIn("recommended route that avoids a carried patch", prompt)
            self.assertIn("maintainer preferences, accepted contribution patterns", prompt)
            self.assertIn("do not open or materially update an upstream issue or pull request", prompt)
            self.assertIn("first-party repository", prompt)
        self.assertIn("return the candidate action and evidence to the parent", worker_prompt)
        self.assertIn("Default toward speculative durable tracking", manager_prompt)
        self.assertIn("invisible lost work", manager_prompt)
        self.assertIn("never a substitute for Work or Result", manager_prompt)
        self.assertIn("Record and review a Result", manager_prompt)
        self.assertIn("Never create or dispatch a worker", manager_prompt)
        self.assertIn("create or update Work, prepare its Assignment", manager_prompt)
        self.assertIn("New and current Work is `active` by default", manager_prompt)
        self.assertIn("Active and open Work is eligible to advance", manager_prompt)
        self.assertIn("pick-before-dispatch preference", manager_prompt)
        self.assertIn("Supervise Work and Assignments as a deliberate loop", manager_prompt)
        self.assertIn("Do not allow returned work to accumulate unreconciled", manager_prompt)
        self.assertIn("Delegate substantive code implementation through its tracked Work and Assignment", manager_prompt)
        self.assertIn("tiny answers, bounded inspection, HUD bookkeeping, and urgent corrective actions", manager_prompt)
        self.assertIn("do not impose a fixed two-worker or other arbitrary concurrency cap", manager_prompt)
        self.assertIn("every available root-owned child slot", manager_prompt)
        self.assertIn("Keep driving actionable Work toward zero", manager_prompt)
        self.assertIn("Do not create agents merely to fill slots or split inseparable work", manager_prompt)
        self.assertIn("not a permanent root-worker cap", manager_prompt)
        self.assertIn("including Grok and cheaper models when suitable", manager_prompt)
        self.assertIn("actively compare the live native Codex option with AgentFX targets", manager_prompt)
        self.assertIn("prefer that fresh AgentFX Grok target for routine, well-specified work", manager_prompt)
        self.assertIn("one explicit `slug_like` Assignment `taskName` first", manager_prompt)
        self.assertIn("pass that identical value as AgentFX `task_slug`", manager_prompt)
        self.assertIn("Do not silently fall back after failed or unknown AgentFX admission", manager_prompt)
        self.assertIn("correctly sized team may use every available root-owned child slot", manager_prompt)
        self.assertIn("Every substantive worker brief", manager_prompt)
        self.assertIn("Missing or ambiguous permission means zero child delegation", manager_prompt)
        self.assertIn("finite numeric limits for direct children and total descendant assignments", manager_prompt)
        self.assertIn("without inferring `waiting`", manager_prompt)
        self.assertIn("until the human acknowledges the substantive Result", manager_prompt)
        self.assertNotIn("There is no universal acknowledgment gate", manager_prompt)
        self.assertNotIn("When the human asks for a sketch",
                         (self.resources / "roles/worker/APPEND_SYSTEM_PROMPT.md").read_text())
        self.assertIn("include resource facts and limitations",
                      (self.resources / "roles/worker/APPEND_SYSTEM_PROMPT.md").read_text())
        retired_mailbox_terms = (
            "agentvoice_thread_mailbox_open",
            "agentvoice.thread_mailbox_notice",
            "remainingCompleted",
            "expectedInstanceId",
        )
        for name in ("manager", "worker"):
            role = self.resources / "roles" / name
            guidance = "\n".join(
                path.read_text()
                for path in role.glob("*.md")
            )
            self.assertIn("agentvoice.subagent_completion", guidance)
            self.assertIn("immediate native parent", guidance)
            for retired in retired_mailbox_terms:
                self.assertNotIn(retired, guidance)


if __name__ == "__main__":
    unittest.main()
