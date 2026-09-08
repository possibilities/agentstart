#!/usr/bin/env python3
"""Hermetic registration tests; never contacts a real Executor or credential store."""

import copy
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import sys
import textwrap
import unittest
from unittest.mock import patch


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


class ProtocolTests(unittest.TestCase):
    path = ["coreTools", "connections", "refresh"]
    arguments = {"owner": "org", "name": "default", "integration": "agentboard"}

    def paused(self, path=None, args=None, ident="exec-test"):
        path = self.path if path is None else path
        args = self.arguments if args is None else args
        address = "executor." + ".".join(path)
        title = "Add an MCP server" if path == ["mcp", "addServer"] else f"Approve {address}?"
        return {"structuredContent": {
            "status": "waiting_for_interaction", "executionId": ident,
            "interaction": {"kind": "form", "address": address, "args": args,
                "message": title + "\n\nArguments:\n" + json.dumps(args, indent=2),
                "requestedSchema": {"type": "object", "properties": {}}},
        }}

    def completed(self, envelope=None):
        return {"structuredContent": {"status": "completed", "result":
            {"ok": True, "data": {"tools": ["guide"]}} if envelope is None else envelope}}

    def invoke_sequence(self, values, calls):
        def invoke(name, args):
            calls.append((name, copy.deepcopy(args)))
            value = values.pop(0)
            if isinstance(value, Exception):
                raise value
            return value
        return invoke

    def test_exact_registry_gate_is_recorded_before_one_accept(self):
        for path, args in [(self.path, self.arguments), (["mcp", "addServer"], registration()[1])]:
            with self.subTest(path=path):
                calls, events = [], []
                invoke = self.invoke_sequence([self.paused(path, args), self.completed()], calls)
                def record(event):
                    events.append(copy.deepcopy(event))
                    if event["status"] == "pending":
                        self.assertEqual(len(calls), 1)
                result = module.api(invoke, path, args, True, record)
                self.assertEqual(result, {"tools": ["guide"]})
                self.assertEqual([call[0] for call in calls], ["execute", "resume"])
                self.assertEqual(calls[1][1], {"executionId": "exec-test", "action": "accept", "content": "{}"})
                self.assertEqual([e["status"] for e in events], ["pending", "resume_returned"])

    def test_unexpected_terms_or_call_are_cancelled_never_accepted(self):
        changes = [
            {"address": "executor.coreTools.policies.create"},
            {"args": {**self.arguments, "integration": "independent"}},
            {"kind": "url", "url": "https://example.com/oauth"},
            {"requestedSchema": {"type": "object", "properties": {"password": {"type": "string"}}}},
            {"meta": {"persistent": True}},
            {"message": "Grant permanent access"},
        ]
        for change in changes:
            with self.subTest(change=change):
                paused, calls, events = self.paused(), [], []
                paused["structuredContent"]["interaction"].update(change)
                invoke = self.invoke_sequence([paused, self.completed()], calls)
                with self.assertRaisesRegex(module.Failure, "unexpected approval.*exec-test"):
                    module.api(invoke, self.path, self.arguments, True, events.append)
                self.assertEqual(calls[1][1]["action"], "cancel")
                self.assertEqual(events[0]["executionId"], "exec-test")

    def test_verify_and_unlisted_operations_never_accept(self):
        path, calls = ["mcp", "getServer"], []
        invoke = self.invoke_sequence([self.paused(path), self.completed()], calls)
        with self.assertRaisesRegex(module.Failure, "unexpected approval"):
            module.api(invoke, path, self.arguments)
        self.assertEqual(calls[1][1]["action"], "cancel")
        for path, install in [(self.path, False), (["coreTools", "policies", "create"], True)]:
            calls = []
            invoke = self.invoke_sequence([], calls)
            with self.assertRaisesRegex(module.Failure, "outside this installer mode"):
                module.api(invoke, path, self.arguments, install)
            self.assertEqual(calls, [])

    def test_malformed_interaction_keeps_id_and_is_cancelled(self):
        paused, calls, events = self.paused(), [], []
        paused["structuredContent"]["interaction"] = ["invalid"]
        invoke = self.invoke_sequence([paused, self.completed()], calls)
        with self.assertRaisesRegex(module.Failure, "exec-test"):
            module.api(invoke, self.path, self.arguments, True, events.append)
        self.assertEqual(calls[1][1]["action"], "cancel")
        self.assertEqual(events[0]["executionId"], "exec-test")

    def test_second_confirmation_stops_even_if_identical(self):
        calls, events = [], []
        invoke = self.invoke_sequence([
            self.paused(), self.paused(ident="exec-nested"), self.completed(),
        ], calls)
        with self.assertRaisesRegex(module.Failure, "exec-nested"):
            module.api(invoke, self.path, self.arguments, True, events.append)
        self.assertEqual([args["action"] for name, args in calls if name == "resume"], ["accept", "cancel"])
        self.assertEqual(events[2]["executionId"], "exec-nested")

    def test_failed_resume_retains_id_and_does_not_retry(self):
        calls, events = [], []
        invoke = self.invoke_sequence([self.paused(), module.Failure("timeout")], calls)
        with self.assertRaisesRegex(module.Failure, "outcome unknown for exec-test"):
            module.api(invoke, self.path, self.arguments, True, events.append)
        self.assertEqual(len(calls), 2)
        self.assertEqual(events, [{"executionId": "exec-test", "requestedAddress":
            "executor.coreTools.connections.refresh", "action": "accept", "status": "pending"}])

    def test_cannot_approve_when_pending_id_cannot_be_persisted(self):
        calls = []
        invoke = self.invoke_sequence([self.paused()], calls)
        def fail_record(_):
            raise OSError("read-only filesystem")
        with self.assertRaisesRegex(module.Failure, "exec-test; no approval sent"):
            module.api(invoke, self.path, self.arguments, True, fail_record)
        self.assertEqual(len(calls), 1)

    def test_completed_execution_does_not_hide_failed_tool(self):
        with self.assertRaisesRegex(module.Failure, "tool failed"):
            module.api(lambda *_: self.completed({"ok": False, "error": {"message": "PRIVATE"}}),
                       ["mcp", "getServer"], {"slug": "agentboard"})

    def test_journal_is_private_and_contains_only_execution_metadata(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "executions.jsonl"
            event = {"executionId": "exec-test", "status": "pending", "action": "accept"}
            module.record_execution(path, event)
            self.assertEqual(json.loads(path.read_text()), event)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_unsafe_existing_journal_is_refused_without_writing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "target"
            target.write_text("preserve these bytes")
            target.chmod(0o600)
            symlink = root / "symlink"
            symlink.symlink_to(target)
            hardlink = root / "hardlink"
            os.link(target, hardlink)
            directory = root / "directory"
            directory.mkdir()
            fifo = root / "fifo"
            os.mkfifo(fifo, 0o600)
            exposed = []
            for mode in [0o640, 0o604, 0o660, 0o606, 0o700]:
                path = root / str(mode)
                path.write_text("preserve these bytes")
                path.chmod(mode)
                exposed.append(path)
            for path in [symlink, hardlink, target, directory, fifo, *exposed]:
                with self.subTest(path=path.name):
                    before = path.lstat()
                    with self.assertRaises(OSError):
                        module.record_execution(path, {"executionId": "must-not-write"})
                    self.assertEqual(path.lstat(), before)
            self.assertEqual(target.read_text(), "preserve these bytes")
            for path in exposed:
                self.assertEqual(path.read_text(), "preserve these bytes")
            foreign = root / "foreign"
            foreign.write_text("independently owned")
            foreign.chmod(0o600)
            with patch.object(module.os, "geteuid", return_value=foreign.stat().st_uid + 1):
                with self.assertRaises(OSError):
                    module.record_execution(foreign, {"executionId": "must-not-write"})
            self.assertEqual(foreign.read_text(), "independently owned")

    def test_stdio_handshake_notifications_structured_result_and_eof(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            executable, ended = root / "executor", root / "eof"
            executable.write_text(f"#!{sys.executable}\n" + textwrap.dedent(f'''
                import json, pathlib, sys
                assert sys.argv[1:] == ['mcp', '--no-artifacts', '--elicitation-mode', 'model']
                for line in sys.stdin:
                    request = json.loads(line)
                    if 'id' not in request:
                        assert request['method'] == 'notifications/initialized'
                        continue
                    if request['method'] == 'initialize':
                        result = {{'protocolVersion':'2025-06-18', 'capabilities':{{'tools':{{}}}}, 'serverInfo':{{'name':'fixture','version':'1'}}}}
                    else:
                        assert request['method'] == 'tools/call'
                        assert request['params']['name'] == 'execute'
                        print(json.dumps({{'jsonrpc':'2.0','method':'notifications/tools/list_changed'}}), flush=True)
                        result = {self.completed()!r}
                    print(json.dumps({{'jsonrpc':'2.0','id':request['id'],'result':result}}), flush=True)
                pathlib.Path({str(ended)!r}).write_text('clean')
            '''))
            executable.chmod(0o755)
            with module.ExecutorMcp(str(executable)) as client:
                self.assertEqual(module.api(client.invoke, ["mcp", "getServer"], {"slug": "agentboard"}),
                                 {"tools": ["guide"]})
            self.assertEqual(ended.read_text(), "clean")
            self.assertEqual(client.process.returncode, 0)


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
