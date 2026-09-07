#!/usr/bin/env python3
"""Hermetic launch, locking, and preservation tests; no provider or account."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "scripts/claude-invocation"
loader = importlib.machinery.SourceFileLoader("claude_invocation", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class Invocation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agentstart-claude-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.cwd = self.root / 'workspace "quoted"'
        self.cwd.mkdir()
        self.source = self.root / "preferences.json"
        self.source.write_text('{"model":"sonnet","permissions":{"defaultMode":"manual"}}\n')
        self.config = self.root / ".claude.json"
        self.original = {"accountFixture": "keep", "projects": {
            "/previous": {"hasTrustDialogAccepted": False, "other": [1]},
            str(self.cwd): {"other": "keep"}}}
        self.config.write_text(json.dumps(self.original))
        self.native = self.root / "native"
        self.native.write_text(f"#!{sys.executable}\nimport json,os,sys\nprint(json.dumps({{'args':sys.argv[1:],'pid':os.getpid(),'input':sys.stdin.read()}}))\nsys.exit(int(os.environ.get('PROBE_EXIT', '0')))\n")
        self.native.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.root),
                    "AGENTSTART_CLAUDE_CONFIG_SOURCE": str(self.source)}
        for key in ("CLAUDE_CONFIG_DIR", "CLAUDE_CODE_CUSTOM_OAUTH_URL", "CLAUDE_CODE_USE_STAGING_OAUTH", "AGENTSTART_CLAUDE_TRUST"):
            self.env.pop(key, None)

    def run_helper(self, *args, **env):
        return subprocess.run([sys.executable, str(HELPER), str(self.native), *args],
                              env={**self.env, **env}, cwd=self.cwd,
                              input="stdin proof", text=True, capture_output=True, timeout=15)

    def test_launch_preserves_stdio_status_settings_and_state(self):
        source = self.source.read_bytes()
        result = self.run_helper("--model", "opus", "hello", PROBE_EXIT="23")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(json.loads(result.stdout)["args"], ["--settings", str(self.source), "--model", "opus", "hello"])
        self.assertEqual(json.loads(result.stdout)["input"], "stdin proof")
        expected = self.original
        expected["projects"][str(self.cwd)]["hasTrustDialogAccepted"] = True
        self.assertEqual(json.loads(self.config.read_text()), expected)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.source.read_bytes(), source)
        self.assertFalse(Path(str(self.config) + ".lock").exists())
        self.assertEqual(list(self.root.glob(".claude.json.agentstart-*")), [])
        before = self.config.stat().st_mtime_ns
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.config.stat().st_mtime_ns, before)

    def test_exec_keeps_process_identity(self):
        child = subprocess.Popen([sys.executable, str(HELPER), str(self.native)], cwd=self.cwd,
                                 env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = child.communicate(timeout=15)
        self.assertEqual(child.returncode, 0, stderr)
        self.assertEqual(json.loads(stdout)["pid"], child.pid)

    def test_admin_and_isolated_modes_are_unchanged(self):
        for args in (("plugin", "disable", "--all"), ("--model", "opus", "auth", "status"), ("--help",), ("--safe-mode",), ("--restricted",), ("--setting-sources", ""), ("--cloud", "task"), ("--future-flag",)):
            before = self.config.read_bytes()
            result = self.run_helper(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["args"], list(args))
            self.assertEqual(self.config.read_bytes(), before)

    def test_option_values_delimiter_and_explicit_settings(self):
        for args in (("--model", "auth"), ("--", "auth", "--help"), ("--resume", "auth"), ("--plugin-dir", "plugin")):
            self.assertEqual(module.inspect(list(args)), (False, False))
        result = self.run_helper("--settings", '{"model":"opus"}')
        self.assertEqual(json.loads(result.stdout)["args"], ["--settings", '{"model":"opus"}'])
        self.source.write_text("malformed unused defaults")
        result = self.run_helper("--settings", '{"model":"opus"}')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_opt_out_and_missing_source(self):
        before = self.config.read_bytes()
        self.assertEqual(self.run_helper(AGENTSTART_CLAUDE_TRUST="0").returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)
        self.source.unlink()
        self.env.pop("AGENTSTART_CLAUDE_CONFIG_SOURCE")
        result = self.run_helper("hi")
        self.assertEqual(json.loads(result.stdout)["args"], ["hi"])
        self.assertEqual(self.config.read_bytes(), before)

    def test_malformed_source_and_state_refuse_without_changing_anything(self):
        for location in (self.source, self.config):
            previous = location.read_bytes()
            location.write_text('{"not valid SECRET')
            before = self.config.read_bytes()
            result = self.run_helper()
            self.assertEqual(result.returncode, 1)
            self.assertNotIn("SECRET", result.stderr)
            self.assertEqual(self.config.read_bytes(), before)
            location.write_bytes(previous)
        self.source.write_text('{"autoMode":{}}')
        self.assertEqual(self.run_helper().returncode, 1)

    def test_native_config_home_and_legacy_paths(self):
        custom = self.root / "profile"
        custom.mkdir()
        for legacy in (False, True):
            expected = custom / (".config.json" if legacy else ".claude.json")
            if legacy:
                expected.write_text('{"legacy":true}')
            self.assertEqual(module.config_path({"HOME": str(self.root), "CLAUDE_CONFIG_DIR": str(custom)}), expected)
            result = self.run_helper(CLAUDE_CONFIG_DIR=str(custom))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(expected.read_text())["projects"][str(self.cwd)]["hasTrustDialogAccepted"])
            self.assertEqual(json.loads(self.config.read_text()), self.original)

    def test_lock_contention_never_steals_or_writes(self):
        lock = Path(str(self.config) + ".lock")
        lock.mkdir()
        os.utime(lock, (1, 1))  # Even a stale native lock is not ours to remove.
        before = self.config.read_bytes()
        with self.assertRaisesRegex(ValueError, "locked"):
            module.trust(self.config, {str(self.cwd)}, timeout=0.05)
        self.assertTrue(lock.is_dir())
        self.assertEqual(self.config.read_bytes(), before)

    def test_simultaneous_launches_merge_and_keep_unrelated_state(self):
        children = []
        for number in range(4):
            cwd = self.root / str(number)
            cwd.mkdir()
            children.append(subprocess.Popen([sys.executable, str(HELPER), str(self.native)], env=self.env,
                            cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        for child in children:
            _, stderr = child.communicate(timeout=15)
            self.assertEqual(child.returncode, 0, stderr)
        data = json.loads(self.config.read_text())
        for number in range(4):
            self.assertTrue(data["projects"][str(self.root / str(number))]["hasTrustDialogAccepted"])
        self.assertEqual(data["accountFixture"], "keep")

    def test_git_worktree_and_physical_cwd(self):
        def git(*args):
            return subprocess.run(["git", *args], cwd=self.cwd, check=True, capture_output=True)
        git("init")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-m", "fixture")
        worktree = self.root / "worktree"
        git("worktree", "add", "--detach", str(worktree))
        subdir = worktree / "sub"
        subdir.mkdir()
        link = self.root / "link"
        link.symlink_to(subdir)
        self.assertEqual(module.workspace_paths(link), {str(subdir), str(worktree), str(self.cwd)})
        with patch.dict(os.environ, {"GIT_DIR": str(self.root / "unrelated"), "GIT_WORK_TREE": str(self.root)}):
            self.assertEqual(module.workspace_paths(link), {str(subdir), str(worktree), str(self.cwd)})

    def test_symlinked_state_is_refused(self):
        target = self.root / "state-target"
        self.config.rename(target)
        self.config.symlink_to(target)
        before = target.read_bytes()
        self.assertEqual(self.run_helper().returncode, 1)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_bytes(), before)

    @unittest.skipUnless(sys.platform == "darwin", "shim installer is macOS-only")
    def test_installed_shim_applies_preferences_and_explicit_bypass(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        (bin_dir / "claude").symlink_to(self.native)
        launcher = bin_dir / "agentlaunch"
        launcher.write_text(f"#!{sys.executable}\nimport os,sys\nassert sys.argv[1:3]==['--x-harness','claude']\nos.environ['AGENTLAUNCH_LAUNCH']='1'\nos.execvp('claude',sys.argv[2:])\n")
        launcher.chmod(0o755)
        shim = self.root / ".local/share/agentlaunch/shims/claude"
        env = {**self.env, "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
               "AGENTLAUNCH_LAUNCH": "", "AGENTLAUNCH_SHIM_BYPASS": ""}
        subprocess.run([str(HELPER.parent / "install-agentlaunch-shims")], env=env, check=True, capture_output=True)
        env["PATH"] = str(shim.parent) + os.pathsep + env["PATH"]
        result = subprocess.run([str(shim), "hello"], env=env, cwd=self.cwd, input="", capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["args"], ["--settings", str(self.source), "hello"])
        before = self.config.read_bytes()
        result = subprocess.run([str(shim), "hello"], env={**env, "AGENTLAUNCH_SHIM_BYPASS": "1"}, cwd=self.cwd, input="", capture_output=True, text=True, timeout=15)
        self.assertEqual(json.loads(result.stdout)["args"], ["hello"])
        self.assertEqual(self.config.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
