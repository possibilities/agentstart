#!/usr/bin/env python3
"""Exercise vendor refresh and repeated supported skill rendering."""

import pathlib
import stat
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RENDERER = ROOT / "scripts/render-terminal-control-skill"
HEADER = b"---\nname: terminal-control\ndescription: Vendor contract.\ndisable-model-invocation: true\n---\n"


class TerminalSkillRender(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.skills = self.root / "skills"
        self.skill = self.skills / "terminal-control"
        self.skill.mkdir(parents=True)
        self.manifest = self.skill / "SKILL.md"
        self.upstream = HEADER + b"# Vendor v1\nSee [details](other.md).\n"
        self.manifest.write_bytes(self.upstream)
        self.manifest.chmod(0o444)
        (self.skill / "other.md").write_text("Vendor sibling")
        self.body = self.root / "body.md"
        self.body.write_text("# Fleet workflow\nUse [CLI](terminal-control-cli.md).\n")
        self.reference = self.skill / "terminal-control-cli.md"

    def render(self, expected=0):
        result = subprocess.run([str(RENDERER), str(self.skills), str(self.body)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)

    def test_repeat_preserves_vendor_frontmatter_reference_siblings_and_mode(self):
        self.render()
        first = self.manifest.read_bytes()
        self.assertTrue(first.startswith(HEADER))
        self.assertIn(b"# Fleet workflow", first)
        self.assertEqual(self.reference.read_bytes(), self.upstream)
        self.assertEqual((self.skill / "other.md").read_text(), "Vendor sibling")
        self.assertEqual(stat.S_IMODE(self.manifest.stat().st_mode), 0o444)
        self.render()
        self.assertEqual(self.manifest.read_bytes(), first)
        self.assertEqual(self.reference.read_bytes(), self.upstream)

    def test_source_update_does_not_replace_the_vendor_reference(self):
        self.render()
        self.body.write_text("# Updated fleet workflow\n")
        self.render()
        self.assertIn(b"# Updated fleet workflow", self.manifest.read_bytes())
        self.assertEqual(self.reference.read_bytes(), self.upstream)

    def test_vendor_refresh_replaces_the_reference_and_preserves_new_frontmatter(self):
        self.render()
        header = HEADER.replace(b"Vendor contract.", b"Vendor v2 contract.")
        upstream = header + b"# Vendor v2\nNew command\n"
        self.manifest.chmod(0o644)
        self.manifest.write_bytes(upstream)
        self.manifest.chmod(0o444)
        self.render()
        self.assertTrue(self.manifest.read_bytes().startswith(header))
        self.assertEqual(self.reference.read_bytes(), upstream)

    def test_missing_saved_vendor_source_fails_without_replacing_manifest(self):
        self.render()
        first = self.manifest.read_bytes()
        self.reference.unlink()
        self.render(1)
        self.assertEqual(self.manifest.read_bytes(), first)

    def test_symlinked_reference_is_not_followed(self):
        self.reference.parent.mkdir(exist_ok=True)
        outside = self.root / "unrelated.md"
        outside.write_text("Keep")
        self.reference.symlink_to(outside)
        self.render(1)
        self.assertEqual(outside.read_text(), "Keep")
        self.assertEqual(self.manifest.read_bytes(), self.upstream)

    def test_missing_optional_vendor_skill_is_a_skip(self):
        other = self.root / "empty"
        other.mkdir()
        result = subprocess.run([str(RENDERER), str(other), str(self.body)], check=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(list(other.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
