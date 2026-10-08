#!/usr/bin/env python3
"""Real LaunchAgent installer boundary; no daemon, token, or live route access."""

import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LABEL = "io.arthack.agentbrain.share"
# Synthetic identities, never a real tailnet name or address.
NEIGHBORS = {
    "TCP": {"8448": {"HTTPS": True}, "48414": {"HTTPS": True}, "10443": {"HTTPS": True}},
    "Web": {
        "device.example:8448": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8799"}}},
        "device.example:48414": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:44414"}}},
        "device.example:10443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:9900"}}},
    },
    "AllowFunnel": {"device.example:10443": True},
    "Services": {"svc:other": {"TCP": {"8888": {"TCPForward": "127.0.0.1:8889"}}}},
    "Foreground": {"reader": {"TCP": {"9443": {"HTTPS": True}}, "Web": {
        "device.example:9443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:3000"}}}
    }}},
}


class ShareNetwork(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agentstart-share-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / ".local/bin"
        self.agents = self.home / "Library/LaunchAgents"
        self.bin.mkdir(parents=True)
        self.agents.mkdir(parents=True)
        self.plist = self.agents / f"{LABEL}.plist"
        self.routes = self.home / "routes.json"
        self.events = self.home / "events"
        self.loaded = self.home / "loaded"
        self.routes.write_text(json.dumps(NEIGHBORS))
        self.env = {
            **os.environ, "HOME": str(self.home), "XDG_STATE_HOME": str(self.home / "state"),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "AGENTSTART_INSTALL_BIN_DIR": str(self.bin),
            "AGENTSTART_INSTALL_LAUNCH_AGENTS_DIR": str(self.agents),
            "AGENTSTART_INSTALL_LAUNCHCTL": str(self.bin / "launchctl"),
            "FIXTURE_ROOT": str(self.home), "FIXTURE_CONNECTED": "1", "FIXTURE_AUTH": "401",
        }
        self.env.pop("AGENTSTART_INSTALL_SHARE_HOST", None)
        self.executable("agentbrain", "#!/bin/sh\nexit 0\n")
        self.executable("tailscale", '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
args = sys.argv[1:]
if args == ["status", "--json"]:
    print(json.dumps({"BackendState": "Running" if os.environ["FIXTURE_CONNECTED"] == "1" else "Stopped"}))
elif args == ["ip", "-4"]:
    print("100.101.102.103" if os.environ["FIXTURE_CONNECTED"] == "1" else "")
elif args == ["serve", "status", "--json"]:
    print((root / "routes.json").read_text())
elif args == ["serve", "--bg", "--tcp=8787", "tcp://127.0.0.1:8787"]:
    with (root / "events").open("a") as f: f.write("publish\\n")
    value = json.loads((root / "routes.json").read_text())
    value.setdefault("TCP", {})["8787"] = {"TCPForward": "127.0.0.1:8787"}
    if os.environ.get("FIXTURE_CORRUPT") == "1":
        value["Web"]["device.example:8448"]["Handlers"]["/"]["Proxy"] = "http://127.0.0.1:1"
    (root / "routes.json").write_text(json.dumps(value))
else:
    raise SystemExit("Unexpected Tailscale mutation/command")
''')
        self.executable("launchctl", '''#!/usr/bin/env python3
import os, pathlib, plistlib, sys
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
args = sys.argv[1:]
if args[0] == "print":
    if not args[1].endswith("/io.arthack.agentbrain.share") or not (root / "loaded").exists(): sys.exit(1)
    print("state = running\\npid = 42")
elif args[0] == "bootout":
    assert args[1].endswith("/io.arthack.agentbrain.share")
    (root / "loaded").unlink()
    with (root / "events").open("a") as f: f.write("bootout\\n")
elif args[0] == "bootstrap":
    with open(args[2], "rb") as f: value = plistlib.load(f)
    assert value["Label"] == "io.arthack.agentbrain.share"
    (root / "loaded").touch()
    with (root / "events").open("a") as f: f.write("bootstrap\\n")
else: sys.exit(1)
''')
        self.executable("lsof", '''#!/usr/bin/env python3
import os, sys
assert sys.argv[1:] == ["-nP", "-a", "-p", "42", "-iTCP", "-sTCP:LISTEN", "-Fpn"]
mode = os.environ.get("FIXTURE_LISTENER", "loopback")
print("p99" if mode == "foreign" else "p42")
print("n*:8787" if mode == "wildcard" else "n127.0.0.1:8787")
''')
        self.executable("curl", '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ["FIXTURE_ROOT"])
args = sys.argv[1:]
assert args[0] == "--disable"  # curlrc cannot inject credentials or change probes
assert "--noproxy" in args and args[args.index("--noproxy") + 1] == "*"
assert not any("Bearer" in a or a.lower() == "authorization:" for a in args)
assert args[-1] in ["http://127.0.0.1:8787/v1/health", "http://127.0.0.1:8787/v1/share", "http://127.0.0.1:8787/v1/shares"]
assert args[args.index("--request") + 1] == ("POST" if args[-1].endswith("/share") else "GET")
with (root / "events").open("a") as f: f.write("probe " + args[-1].rsplit("/", 1)[-1] + "\\n")
code = os.environ["FIXTURE_AUTH"] if args[-1].endswith(os.environ.get("FIXTURE_AUTH_PATH", "")) else "401"
print(json.dumps({"schema_version": 1, "ok": False, "error": {"code": "unauthorized"}}))
print(code)
''')

    def executable(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(0o755)

    def install(self, mode="--install"):
        return subprocess.run([str(ROOT / "scripts/install-launchagents"), mode, "--service", LABEL],
                              env=self.env, text=True, capture_output=True)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_loopback_listener_preserves_client_port_and_neighbor_routes(self):
        self.assert_ok(self.install())
        with self.plist.open("rb") as f:
            value = plistlib.load(f)
        self.assertEqual(value["ProgramArguments"], [str(self.bin / "agentbrain"), "share", "serve",
                                                     "--host", "127.0.0.1", "--port", "8787"])
        self.assertEqual(value["EnvironmentVariables"].keys(), {"HOME", "PATH"})
        expected = json.loads(json.dumps(NEIGHBORS))
        expected["TCP"]["8787"] = {"TCPForward": "127.0.0.1:8787"}
        self.assertEqual(json.loads(self.routes.read_text()), expected)
        self.assertEqual(self.events.read_text().splitlines(),
                         ["bootstrap", "probe health", "probe share", "probe shares", "publish"])

    def old_listener(self):
        # Independent old installation, not rendered from the changing template.
        value = {"Label": LABEL, "ProgramArguments": [str(self.bin / "agentbrain"), "share", "serve",
                                                     "--host", "100.101.102.103"]}
        data = plistlib.dumps(value).decode().splitlines(keepends=True)
        data.insert(2, f"<!-- agentstart-installer-owned: {LABEL}.v1 -->\n")
        self.plist.write_text("".join(data))
        self.loaded.touch()

    def test_owned_tailnet_listener_cutover_is_narrow_and_ordered(self):
        self.old_listener()
        self.assert_ok(self.install())
        self.assertEqual(self.events.read_text().splitlines(),
                         ["bootout", "bootstrap", "probe health", "probe share", "probe shares", "publish"])

    def test_conflicts_refuse_before_rewriting_or_restarting_listener(self):
        cases = {
            "public-root": {"TCP": {"443": {"HTTPS": True}},
                            "Web": {"device.example:443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8787"}}}},
                            "AllowFunnel": {"device.example:443": True}},
            "public-raw-tcp": {"TCP": {"443": {"TCPForward": "localhost:8787"}},
                               "AllowFunnel": {"device.example:443": True}},
            "public-8787": {"AllowFunnel": {"device.example:8787": True}},
            "foreign-tcp": {"TCP": {"8787": {"TCPForward": "127.0.0.1:8799"}}},
            "tls-termination": {"TCP": {"8787": {**{"TCPForward": "127.0.0.1:8787"}, "TerminateTLS": "device.example"}}},
            "proxy-protocol": {"TCP": {"8787": {"TCPForward": "127.0.0.1:8787", "ProxyProtocol": 1}}},
            "http-handler": {"TCP": {"8787": {"HTTP": True}}},
            "orphan-web-handler": {"Web": {"device.example:8787": {"Handlers": {"/": {"Text": "foreign"}}}}},
            "foreground-port": {"Foreground": {"session": {"TCP": {"8787": {"TCPForward": "127.0.0.1:8787"}}}}},
            "foreground-public": {"Foreground": {"session": {
                "Web": {"device.example:443": {"Handlers": {"/nested": {"Proxy": "8787"}}}},
                "AllowFunnel": {"device.example:443": True}}}},
        }
        self.old_listener()
        for name, routes in cases.items():
            with self.subTest(name=name):
                self.routes.write_text(json.dumps(routes))
                before_plist, before_routes = self.plist.read_bytes(), self.routes.read_bytes()
                result = self.install()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertRegex(result.stderr, "Public|Foreign")
                self.assertEqual(self.plist.read_bytes(), before_plist)
                self.assertEqual(self.routes.read_bytes(), before_routes)
                self.assertTrue(self.loaded.exists())
                self.assertFalse(self.events.exists())

    def test_repeat_install_does_not_rewrite_restart_or_republish(self):
        self.assert_ok(self.install())
        before = (self.plist.read_bytes(), self.plist.stat().st_ino, self.plist.stat().st_mtime_ns,
                  self.routes.read_bytes(), self.routes.stat().st_mtime_ns)
        self.events.write_text("")
        self.assert_ok(self.install())
        after = (self.plist.read_bytes(), self.plist.stat().st_ino, self.plist.stat().st_mtime_ns,
                 self.routes.read_bytes(), self.routes.stat().st_mtime_ns)
        self.assertEqual(after, before)
        self.assertEqual(self.events.read_text().splitlines(), ["probe health", "probe share", "probe shares"])

    def test_check_is_read_only_and_status_detects_missing_route(self):
        before = self.routes.read_bytes()
        self.assert_ok(self.install("--check"))
        self.assertEqual(self.routes.read_bytes(), before)
        self.assertFalse(self.plist.exists())
        self.assertFalse(self.events.exists())
        self.assert_ok(self.install())
        self.assert_ok(self.install("--status"))
        self.routes.write_bytes(before)
        result = self.install("--status")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("route missing", result.stderr)
        self.assertEqual(self.routes.read_bytes(), before)

    def test_off_tailnet_absent_skips_and_installed_service_stays_running(self):
        self.env["FIXTURE_CONNECTED"] = "0"
        before = self.routes.read_bytes()
        self.assert_ok(self.install())
        self.assertFalse(self.plist.exists())
        self.assertEqual(self.routes.read_bytes(), before)
        self.assertFalse(self.events.exists())
        self.env["FIXTURE_CONNECTED"] = "1"
        self.assert_ok(self.install())
        before = (self.plist.read_bytes(), self.routes.read_bytes())
        self.events.write_text("")
        self.env["FIXTURE_CONNECTED"] = "0"
        self.assert_ok(self.install())
        self.assertEqual((self.plist.read_bytes(), self.routes.read_bytes()), before)
        self.assertEqual(self.events.read_text().splitlines(), ["probe health", "probe share", "probe shares"])

    def test_missing_tailscale_never_cuts_over_unknown_public_state(self):
        self.executable("tailscale", "#!/bin/sh\nexit 1\n")
        self.assert_ok(self.install())
        self.assertFalse(self.plist.exists())
        self.old_listener()
        before = self.plist.read_bytes()
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(self.plist.read_bytes(), before)
        self.assertFalse(self.events.exists())

    def test_every_data_api_must_reject_without_a_token_before_publication(self):
        self.env["FIXTURE_AUTH"] = "200"
        for path in ("health", "share", "shares"):
            with self.subTest(path=path):
                self.env["FIXTURE_AUTH_PATH"] = "/" + path
                before = self.routes.read_bytes()
                result = self.install()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not reject", result.stderr)
                self.assertEqual(self.routes.read_bytes(), before)
                self.assertNotIn("publish", self.events.read_text())

    def test_route_publication_checks_unrelated_omajot_postcondition(self):
        self.env["FIXTURE_CORRUPT"] = "1"
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unrelated routes changed", result.stderr)

    def test_probe_cannot_publish_a_foreign_or_wildcard_listener(self):
        for listener in ("foreign", "wildcard"):
            with self.subTest(listener=listener):
                self.env["FIXTURE_LISTENER"] = listener
                before = self.routes.read_bytes()
                result = self.install()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("foreign or non-loopback listener", result.stderr)
                self.assertEqual(self.routes.read_bytes(), before)
                self.assertNotIn("publish", self.events.read_text())

    def test_foreign_share_job_is_never_replaced_or_published(self):
        self.plist.write_text("<!-- foreign -->\n")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual(self.plist.read_text(), "<!-- foreign -->\n")
        self.assertFalse(self.events.exists())


if __name__ == "__main__":
    unittest.main()
