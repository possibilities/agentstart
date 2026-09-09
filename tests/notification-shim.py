#!/usr/bin/env python3
"""Exercise installed routing without posting to either real notification app."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = '''#!/usr/bin/python3
import json, os, signal, sys, time
kind = os.path.basename(sys.argv[0])
with open(os.environ['ROUTE_LOG'], 'a') as log:
    log.write(json.dumps([kind, sys.argv[1:]]) + '\\n')
if kind == 'agentnotify' and sys.argv[1:] == ['diagnose']:
    time.sleep(float(os.environ.get('PROBE_DELAY', '0')))
    print('diagnostic output must stay private')
    sys.exit(int(os.environ.get('PROBE_EXIT', '0')))
if os.environ.get('ACTION_SIGNAL'):
    os.kill(os.getpid(), signal.SIGTERM)
print(json.dumps({'backend': kind, 'args': sys.argv[1:], 'stdin': sys.stdin.read()}))
sys.exit(int(os.environ.get('ACTION_EXIT', '0')))
'''


class NotificationShimTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='notifier route ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        self.primary = self.bin / 'agentnotify'
        self.primary.write_text(FIXTURE); self.primary.chmod(0o755)
        self.fallback = self.home / 'original-notifier'
        self.fallback.write_text(FIXTURE); self.fallback.chmod(0o755)
        self.log = self.home / 'calls'
        self.env = {**os.environ, 'HOME': str(self.home), 'PATH': '/usr/bin:/bin',
                    'AGENTSTART_INSTALL_BIN_DIR': str(self.bin), 'ROUTE_LOG': str(self.log),
                    'AGENTSTART_TERMINAL_NOTIFIER_FALLBACK': str(self.fallback)}
        self.shim = self.bin / 'terminal-notifier'
        self.assertEqual(self.install().returncode, 0)

    def install(self):
        return subprocess.run([str(ROOT / 'scripts/install-notification-shim')], env=self.env,
                              text=True, capture_output=True, timeout=10)

    def run_shim(self, args=None, **env):
        return subprocess.run([str(self.shim), *(args or ['-message', 'a literal $(command) `value`'])],
                              input='piped message\nsecond line\n', env={**self.env, **env},
                              text=True, capture_output=True, timeout=20)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_primary_preserves_literal_arguments_stdin_and_output(self):
        result = self.run_shim(['-reply', 'Your answer', '-action', 'One,Two'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertEqual(json.loads(result.stdout), {'backend': 'agentnotify', 'args': ['-reply', 'Your answer', '-action', 'One,Two'], 'stdin': 'piped message\nsecond line\n'})
        self.assertEqual(len(self.calls()), 2)

    def test_unavailable_primary_falls_back_before_submission(self):
        for missing in [False, True]:
            with self.subTest(missing=missing):
                if missing: self.primary.unlink()
                result = self.run_shim(PROBE_EXIT='4')
                self.assertEqual(result.returncode, 0)
                self.assertEqual(json.loads(result.stdout)['backend'], 'original-notifier')
                self.assertEqual(json.loads(result.stdout)['stdin'], 'piped message\nsecond line\n')
        self.assertTrue(all(args == ['diagnose'] for kind, args in self.calls() if kind == 'agentnotify'))

    def test_dispatch_failure_timeout_or_denial_never_replays(self):
        for code in [2, 3, 4, 5, 6]:
            with self.subTest(code=code):
                result = self.run_shim(ACTION_EXIT=str(code))
                self.assertEqual(result.returncode, code)
                self.assertEqual(json.loads(result.stdout)['backend'], 'agentnotify')
        self.assertFalse(any(kind == 'original-notifier' for kind, _ in self.calls()))

    def test_signal_is_preserved_after_dispatch(self):
        self.assertEqual(self.run_shim(ACTION_SIGNAL='1').returncode, -signal.SIGTERM)
        self.assertFalse(any(kind == 'original-notifier' for kind, _ in self.calls()))

    def test_probe_is_bounded_and_then_uses_fallback(self):
        result = self.run_shim(PROBE_DELAY='30')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['backend'], 'original-notifier')

    def test_missing_both_backends_fails_without_submission(self):
        self.primary.unlink(); self.fallback.unlink()
        self.assertEqual(self.run_shim().returncode, 127)
        self.assertEqual(self.calls(), [])

    def test_path_search_skips_the_router_and_its_alias(self):
        self.primary.unlink()
        alias = self.home / 'aliases'; alias.mkdir()
        (alias / 'terminal-notifier').symlink_to(self.shim)
        native = self.home / 'native'; native.mkdir()
        (native / 'terminal-notifier').symlink_to(self.fallback)
        self.env.pop('AGENTSTART_TERMINAL_NOTIFIER_FALLBACK')
        result = self.run_shim(PATH=os.pathsep.join(map(str, [self.bin, alias, native])))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['backend'], 'terminal-notifier')

    def test_installer_is_rerunnable_migrates_owned_alias_and_preserves_foreign_files(self):
        self.assertEqual(self.install().returncode, 0)
        self.shim.unlink()
        self.shim.symlink_to(self.home / 'Applications/AgentNotify.app/Contents/MacOS/AgentNotify')
        self.assertEqual(self.install().returncode, 0)
        self.assertFalse(self.shim.is_symlink())
        self.shim.write_text('foreign command')
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(self.shim.read_text(), 'foreign command')
        self.shim.unlink(); self.shim.symlink_to(self.fallback)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(self.shim.resolve(), self.fallback)


if __name__ == '__main__':
    unittest.main()
