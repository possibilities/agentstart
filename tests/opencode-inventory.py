#!/usr/bin/env python3
"""Black-box checks for the read-only OpenCode V2 inventory command."""

import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/opencode-inventory"
SCHEMA = """
CREATE TABLE session_v2 (
  id TEXT PRIMARY KEY, title TEXT, parent_id TEXT, directory TEXT,
  version TEXT, agent TEXT, time_created INTEGER, time_updated INTEGER,
  time_idle INTEGER, time_suspended INTEGER, time_archived INTEGER
);
CREATE TABLE session_message (body TEXT);
"""


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agentstart-inventory-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def database(self, name="opencode.db"):
        path = self.root / name
        db = sqlite3.connect(path)
        db.executescript(SCHEMA)
        db.execute("INSERT INTO session_message VALUES (?)", ("SECRET MESSAGE BODY",))
        db.commit()
        self.addCleanup(db.close)
        return path, db

    def row(self, db, id, title, parent=None, directory="/repo", updated=2000,
            idle=None, suspended=None):
        db.execute(
            "INSERT INTO session_v2 VALUES (?, ?, ?, ?, '2.0.16', 'build', 1000, ?, ?, ?, NULL)",
            (id, title, parent, directory, updated, idle, suspended),
        )
        db.commit()

    def run_script(self, *arguments, env=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, arguments)],
            capture_output=True, text=True, timeout=10, env=env,
        )

    def test_live_wal_inventory_preserves_parent_and_distinguishes_recorded_idle(self):
        path, db = self.database()
        db.execute("PRAGMA journal_mode=WAL")
        self.row(db, "ses_root", "Current title", idle=3000)
        self.row(db, "ses_child", "Child title", "ses_root", "/repo/child", updated=4000)
        self.row(db, "ses_funk_keepalive_v1_x", "Funk OpenCode keepalive (no prompts)")
        result = self.run_script("--db", path, "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("SECRET MESSAGE BODY", result.stdout)
        data = json.loads(result.stdout)
        self.assertEqual(data["total_records"], 3)
        self.assertEqual(data["hidden_keepalive"], 1)
        self.assertEqual({item["id"] for item in data["sessions"]}, {"ses_root", "ses_child"})
        child = next(item for item in data["sessions"] if item["id"] == "ses_child")
        root = next(item for item in data["sessions"] if item["id"] == "ses_root")
        self.assertEqual(child["parent_id"], root["id"])
        self.assertEqual(root["recorded_state"], "idle_recorded")
        self.assertEqual(child["recorded_state"], "undetermined")
        self.assertIn("do not prove", data["activity_note"])
        roots = json.loads(self.run_script("--db", path, "--json", "--roots-only").stdout)
        self.assertEqual([item["id"] for item in roots["sessions"]], ["ses_root"])
        child_only = json.loads(self.run_script(
            "--db", path, "--json", "--directory", "/repo/child"
        ).stdout)
        self.assertEqual([item["id"] for item in child_only["sessions"]], ["ses_child"])

    def test_multiple_databases_and_processes_remain_separate_observations(self):
        first, a = self.database("first.db")
        second, b = self.database("second.db")
        self.row(a, "ses_one", "One")
        self.row(b, "ses_two", "Two", suspended=3000)
        bindir = self.root / "bin"
        bindir.mkdir()
        ps = bindir / "ps"
        ps.write_text("#!/bin/sh\nprintf '2302 2300 /opt/opencode\\n2303 2302 /opt/opencode.exe\\n7 1 /bin/other\\n'\n")
        ps.chmod(0o755)
        lsof = bindir / "lsof"
        lsof.write_text("#!/bin/sh\nprintf 'p%s\\nn/workspace\\n' \"$3\"\n")
        lsof.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir))
        result = self.run_script("--db", first, "--db", second, "--json", "--processes", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(len(data["databases"]), 2)
        self.assertEqual({item["source_db"] for item in data["sessions"]}, set(data["databases"]))
        self.assertEqual([item["pid"] for item in data["processes"]], [2302, 2303])
        self.assertTrue(all(item["cwd"] == "/workspace" for item in data["processes"]))
        self.assertEqual(next(item for item in data["sessions"]
                              if item["id"] == "ses_two")["recorded_state"], "suspended")

    def test_missing_changed_and_locked_databases_fail_without_tracebacks_or_bodies(self):
        missing = self.run_script("--db", self.root / "missing.db")
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("database unavailable", missing.stderr)

        changed = self.root / "changed.db"
        with sqlite3.connect(changed) as db:
            db.execute("CREATE TABLE session_v2 (id TEXT)")
        result = self.run_script("--db", changed)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported session_v2 schema", result.stderr)

        path, db = self.database("locked.db")
        db.execute("BEGIN EXCLUSIVE")
        try:
            locked = self.run_script("--db", path)
        finally:
            db.rollback()
        self.assertNotEqual(locked.returncode, 0)
        self.assertIn("cannot read OpenCode V2 database", locked.stderr)
        self.assertNotIn("Traceback", locked.stderr)


if __name__ == "__main__":
    unittest.main()
