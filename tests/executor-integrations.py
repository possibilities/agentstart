#!/usr/bin/env python3
"""Hermetic registration tests; never contacts a real Executor or credential store."""

import copy
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import sys
import unittest


sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("executor_integrations", str(ROOT / "scripts/executor-integrations"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def registration(slug="agentboard", args=None):
    entry = {"slug": slug, "name": slug, "transport": "stdio", "command": slug, "args": args or ["mcp"]}
    desired = module.config({k: v for k, v in entry.items() if k in module.CONFIG_FIELDS})
    return slug, entry, desired, False


class Catalog:
    def __init__(self, auto_connect=True):
        self.servers = {}
        self.connections = []
        self.mutations = []
        self.auto_connect = auto_connect
        self.healthy = True

    def default(self, slug):
        return {"owner": "org", "integration": slug, "name": "default", "template": "none"}

    def call(self, path, args):
        operation = path[-1]
        slug = args.get("slug", args.get("integration"))
        if operation == "getServer":
            return {"integration": copy.deepcopy(self.servers.get(slug))}
        if operation == "list":
            return {"connections": copy.deepcopy([c for c in self.connections if c["integration"] == slug])}
        self.mutations.append((operation, copy.deepcopy(args)))
        if operation == "addServer":
            if slug in self.servers:
                raise AssertionError("duplicate integration")
            config = {k: v for k, v in args.items() if k in module.CONFIG_FIELDS}
            config["authenticationTemplate"] = [{"slug": "none", "kind": "none"}]
            self.servers[slug] = {"config": config}
            if self.auto_connect:
                self.connections.append(self.default(slug))
            return {"slug": slug}
        if operation == "create":
            if any(c["integration"] == slug and c["name"] == args["name"] and c["owner"] == args["owner"] for c in self.connections):
                raise AssertionError("duplicate connection")
            self.connections.append(copy.deepcopy(args))
            return args
        if operation == "refresh":
            return {"tools": [{"name": "guide"}] if self.healthy else [],
                    "lastHealth": {"status": "healthy" if self.healthy else "degraded"}}
        if operation == "remove":
            del self.servers[slug]
            self.connections = [c for c in self.connections if c["integration"] != slug]
            return {"removed": True}
        raise AssertionError(path)


class RegistrationTests(unittest.TestCase):
    def test_new_auto_connected_server_and_idempotent_rerun(self):
        catalog, records = Catalog(), {}
        saved = []
        for _ in range(2):
            module.converge([registration()], catalog.call, records, True,
                            lambda rows: saved.append(copy.deepcopy(rows)))
        self.assertEqual([op for op, _ in catalog.mutations], ["addServer", "refresh", "refresh"])
        self.assertEqual(len(saved), 2)
        self.assertEqual(len(catalog.connections), 1)
        catalog.mutations.clear()
        module.converge([registration()], catalog.call, records, False, lambda _: self.fail("verify wrote a receipt"))
        self.assertEqual(catalog.mutations, [])

    def test_older_executor_needs_one_explicit_default(self):
        catalog = Catalog(auto_connect=False)
        module.converge([registration()], catalog.call, {}, True, lambda _: None)
        self.assertEqual([op for op, _ in catalog.mutations], ["addServer", "create", "refresh"])

    def test_adopts_exact_existing_registration_without_touching_other_accounts(self):
        catalog = Catalog()
        entry = registration()
        catalog.call(["mcp", "addServer"], entry[1])
        catalog.servers["mail"] = {"config": {"transport": "remote", "endpoint": "https://example.com"}}
        catalog.connections.append({"integration": "mail", "name": "personal", "owner": "user", "template": "oauth"})
        prior_mail = copy.deepcopy((catalog.servers["mail"], catalog.connections[-1]))
        catalog.mutations.clear()
        records = {}
        module.converge([entry], catalog.call, records, True, lambda _: None)
        self.assertEqual([op for op, _ in catalog.mutations], ["refresh"])
        self.assertEqual(prior_mail, (catalog.servers["mail"], catalog.connections[-1]))
        self.assertEqual(records[entry[0]], entry[2])

    def test_foreign_drift_fails_before_adding_another_missing_server(self):
        catalog = Catalog()
        old = registration(args=["mcp", "--independent"])
        catalog.call(["mcp", "addServer"], old[1])
        catalog.mutations.clear()
        with self.assertRaisesRegex(module.Failure, "preserved"):
            module.converge([registration("agentbrain"), registration()], catalog.call, {}, True, lambda _: None)
        self.assertEqual(catalog.mutations, [])
        self.assertNotIn("agentbrain", catalog.servers)

    def test_owned_source_change_recreates_only_proven_no_auth_registration(self):
        catalog, records = Catalog(), {}
        module.converge([registration()], catalog.call, records, True, lambda _: None)
        catalog.mutations.clear()
        updated = registration(args=["mcp", "--new"])
        module.converge([updated], catalog.call, records, True, lambda _: None)
        self.assertEqual([op for op, _ in catalog.mutations], ["remove", "addServer", "refresh"])
        self.assertEqual(records["agentboard"], updated[2])

    def test_new_independent_connection_prevents_replacement(self):
        catalog, records = Catalog(), {}
        module.converge([registration()], catalog.call, records, True, lambda _: None)
        catalog.connections.append({"integration": "agentboard", "owner": "user", "name": "mine", "template": "none"})
        catalog.mutations.clear()
        with self.assertRaisesRegex(module.Failure, "preserved"):
            module.converge([registration(args=["mcp", "--new"])], catalog.call, records, True, lambda _: None)
        self.assertEqual(catalog.mutations, [])

    def test_authenticated_default_is_never_replaced(self):
        catalog = Catalog()
        catalog.call(["mcp", "addServer"], registration()[1])
        catalog.connections[0]["template"] = "stdio_env"
        catalog.mutations.clear()
        with self.assertRaisesRegex(module.Failure, "independently authenticated"):
            module.converge([registration()], catalog.call, {}, True, lambda _: None)
        self.assertEqual(catalog.mutations, [])

    def test_failed_discovery_does_not_record_success_and_rerun_recovers(self):
        catalog, records = Catalog(), {}
        catalog.healthy = False
        with self.assertRaisesRegex(module.Failure, "healthy nonempty"):
            module.converge([registration()], catalog.call, records, True, lambda _: self.fail("saved failed install"))
        self.assertEqual(records, {})
        catalog.healthy = True
        module.converge([registration()], catalog.call, records, True, lambda _: None)
        self.assertIn("agentboard", records)

    def test_env_round_trips_and_credentials_are_not_adopted(self):
        expected = module.config({"transport": "stdio", "command": "codex", "staticEnv": {"CODEX_HOME": "/tmp/codex"}})
        actual = module.config({"transport": "stdio", "command": "codex", "env": {"CODEX_HOME": "/tmp/codex"}, "family": "tools"})
        self.assertEqual(expected, actual)
        with self.assertRaisesRegex(module.Failure, "credential-bearing"):
            module.config({"transport": "stdio", "command": "codex", "authenticationTemplate": [{"slug": "key", "kind": "stdio_env"}]})

    def test_source_manifest_expands_paths_without_shell_evaluation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "code/agentboard").mkdir(parents=True)
            rows = module.load_manifest(ROOT / "config/executor/integrations.json", root, root / "code")
            desktop = next(row for row in rows if row[0] == "codex_computer_use")
            self.assertEqual(desktop[1]["command"], str(root / ".local/bin/codex"))
            self.assertEqual(desktop[2]["env"]["CODEX_HOME"], str(root / ".codex"))
            self.assertFalse(next(row for row in rows if row[0] == "agentboard")[3])
            self.assertTrue(next(row for row in rows if row[0] == "agentbrain")[3])
            path = root / "receipt.json"
            module.save_receipt(path, {desktop[0]: desktop[2]})
            self.assertEqual(json.loads(path.read_text())["owner"], module.OWNER)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
