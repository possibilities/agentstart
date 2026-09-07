#!/usr/bin/env python3
"""Offline stock-Codex lifecycle proof. Usage: python3 tests/codex-invocation-runtime.py /absolute/native/codex

Uses a disposable Codex home and a loopback Responses fixture, with no real
credentials or remote model requests. All child processes/server threads end.
"""
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading

requests = []


class Provider(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        requests.append(json.loads(body))
        n = len(requests)
        item = {"type": "message", "id": "msg_%s" % n, "status": "completed", "role": "assistant",
                "content": [{"type": "output_text", "text": "offline-proof-%s" % n, "annotations": []}]}
        response = {"id": "resp_%s" % n, "object": "response", "status": "completed",
                    "output": [item], "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}}
        events = [
            {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
            {"type": "response.output_item.added", "output_index": 0, "item": {**item, "status": "in_progress", "content": []}},
            {"type": "response.content_part.added", "item_id": item["id"], "output_index": 0, "content_index": 0,
             "part": {"type": "output_text", "text": "", "annotations": []}},
            {"type": "response.output_text.delta", "item_id": item["id"], "output_index": 0, "content_index": 0,
             "delta": "offline-proof-%s" % n},
            {"type": "response.output_item.done", "output_index": 0, "item": item},
            {"type": "response.completed", "response": response},
        ]
        payload = "".join("data: " + json.dumps(event) + "\n\n" for event in events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main():
    native = str(Path(sys.argv[1]).resolve(strict=True))
    helper = Path(__file__).resolve().parents[1] / "scripts/codex-invocation"
    server = http.server.HTTPServer(("127.0.0.1", 0), Provider)
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="codex-invocation-runtime-") as temp:
            root = Path(temp).resolve()
            codex_dir = root / "codex"
            codex_dir.mkdir()
            repo = root / 'work.tree with spaces'
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            nested = repo / "child"
            nested.mkdir()
            (repo / ".codex").mkdir()
            (repo / ".codex/config.toml").write_text('model_reasoning_effort="low"\n')
            source = root / "authored.toml"
            source.write_text('model="gpt-5.5"\nmodel_reasoning_effort="high"\n')
            base = '''model="ambient-unused"
model_provider="fixture"
check_for_update_on_startup=false
[model_providers.fixture]
name="Offline fixture"
base_url="http://127.0.0.1:%s/v1"
wire_api="responses"
supports_websockets=false
[features]
apps=false
remote_plugin=false
hooks=false
shell_snapshot=false
[analytics]
enabled=false
''' % server.server_port
            (codex_dir / "config.toml").write_text(base)
            env = {key: value for key, value in os.environ.items() if key in ("HOME", "PATH", "TMPDIR", "LANG", "TERM")}
            env.update(CODEX_HOME=str(codex_dir), AGENTSTART_CODEX_CONFIG_SOURCE=str(source))

            def run(args):
                p = subprocess.Popen([str(helper), native, *args], cwd=nested, env=env,
                                     stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, start_new_session=True)
                try:
                    stdout, stderr = p.communicate(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGTERM)
                    try:
                        p.communicate(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.communicate()
                    raise
                if p.returncode:
                    raise AssertionError("Codex failed (%s):\n%s\n%s" % (p.returncode, stdout, stderr))
                assert (codex_dir / "config.toml").read_text() == base
                assert not list(codex_dir.glob("agentstart-invocation-*.config.toml"))
                return [json.loads(line) for line in stdout.splitlines() if line.startswith("{")]

            events = run(["exec", "--json", "Return the fixture response."])
            thread_id = next(e["thread_id"] for e in events if e["type"] == "thread.started")
            assert requests[-1]["model"] == "gpt-5.5", requests[-1].get("model")
            assert requests[-1]["reasoning"]["effort"] == "low", "root project config was not trusted from nested cwd"
            assert source.read_text() == 'model="gpt-5.5"\nmodel_reasoning_effort="high"\n'
            source.write_text('model="gpt-5.6-sol"\nmodel_reasoning_effort="high"\n')
            resume_start = len(requests)
            resumed = run(["exec", "resume", thread_id, "--json", "Continue the saved conversation."])
            assert requests[-1]["model"] == "gpt-5.6-sol", "resume did not use the new invocation profile"
            assert next(e["thread_id"] for e in resumed if e["type"] == "thread.started") == thread_id
            # A model switch can compact first; the saved reply must reach
            # that resume request, not necessarily the post-compaction one.
            assert any("offline-proof-1" in json.dumps(r["input"]) for r in requests[resume_start:]), "resume lost saved history"
            assert source.read_text() == 'model="gpt-5.6-sol"\nmodel_reasoning_effort="high"\n'
            print("PASS stock Codex: trusted nested project config, model turn, saved history, resume with fresh preferences, source/base preservation, profile cleanup")
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join()


if __name__ == "__main__":
    main()
