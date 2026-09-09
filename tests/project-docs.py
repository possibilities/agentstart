#!/usr/bin/env python3
"""Document integrity fixtures: real regressions, portable to an empty machine."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-project-docs.py"
SPEC = importlib.util.spec_from_file_location("project_docs", SCRIPT)
DOCS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DOCS)


class ProjectDocsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def findings(self, excludes=()):
        return DOCS.check_repository(self.root, excludes)["findings"]

    def test_colliding_identity_fails_but_historical_namespace_is_explicit(self):
        self.write("docs/adr/0001-first.md", "# 0001: First\n")
        self.write("docs/adr/0001-second.md", "# 0001: Second\n")
        self.write("docs/adr/superseded/0001-old.md", "# 0001: Old\n")
        findings = self.findings()
        self.assertEqual([item["code"] for item in findings], ["duplicate-adr-id"])
        self.assertIn("0001-first.md", findings[0]["message"])
        self.assertEqual(self.findings(["docs/adr/0001-second.md"]), [])

    def test_missing_replacement_target_is_an_error_with_location(self):
        self.write("docs/adr/0001-first.md", "# First\n\nSuperseded by [second](0002-second.md).\n")
        item, = self.findings()
        self.assertEqual((item["code"], item["line"]), ("missing-local-target", 3))
        self.write("docs/adr/0002-second.md", "# Second\n")
        self.assertEqual(self.findings(), [])

    def test_real_links_are_checked_but_examples_and_external_paths_are_skipped(self):
        self.write("docs/with space.md", "# Target\n")
        self.write("AGENTS.md", """# Guidance
Read [`the guide`](docs/with%20space.md#part).
[Other form](<docs/with space.md>)
[reference]: docs/with%20space.md "Title"
[web](https://example.invalid/not-local.md) and [anchor](#local)
[machine](/machine-only/file.md) and [home](~/code/file.md)
`[inline example](missing.md)`
```md
[fenced example](missing.md)
```
    [indented example](missing.md)
""")
        self.assertEqual(self.findings(), [])
        self.write("docs/current.md", "[reference]: removed.md\n")
        self.assertEqual([item["code"] for item in self.findings()], ["missing-local-target"])

    def test_glossary_and_unlinked_replacement_are_advisory(self):
        self.write("CONTEXT.md", "# Terms\n")
        self.write("docs/adr/0001-first.md", "# First\n\nSuperseded by ADR 0002.\n")
        self.assertEqual({item["code"] for item in self.findings()}, {"replacement-link", "glossary-entrypoint"})
        self.assertTrue(all(item["level"] == "warning" for item in self.findings()))
        self.write("docs/adr/0002-upgrade.md", "# Upgrade\nThe installation is replaced by a signed release.\n")
        self.assertEqual(len(self.findings()), 2)

    def test_entrypoint_symlink_is_checked_and_regular_pointer_is_allowed(self):
        (self.root / "CLAUDE.md").symlink_to("AGENTS.md")
        self.assertEqual([item["code"] for item in self.findings()], ["broken-symlink"])
        self.write("AGENTS.md", "# Guidance\n")
        self.assertEqual(self.findings(), [])
        (self.root / "CLAUDE.md").unlink()
        self.write("CLAUDE.md", "Read AGENTS.md.\n")
        self.assertEqual(self.findings(), [])

    def test_git_ignored_documents_are_outside_the_check(self):
        self.write(".gitignore", "docs/vendor/\n")
        self.write("docs/vendor/README.md", "[foreign](missing.md)\n")
        self.assertEqual(self.findings(), [])


if __name__ == "__main__":
    unittest.main()
