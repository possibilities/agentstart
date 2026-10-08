#!/usr/bin/env python3
"""Bounded private TCP ingress convergence for the AgentStart-owned share job.

Called before listener cutover and after launchd convergence. Never reads a
token, replaces a conflicting handler, or submits a whole Serve configuration.
"""

import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit


PORT = "8787"
FORWARD = {"TCPForward": "127.0.0.1:8787"}


class Refusal(Exception):
    pass


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        raise Refusal(f"{args[0]} unavailable or timed out; no automatic retry") from None


def read_json(args):
    result = run(args)
    if result.returncode:
        raise Refusal(f"{args[0]} {args[1]} failed; inspect that tool's status")
    try:
        value = json.loads(result.stdout)
    except ValueError:
        raise Refusal(f"{args[0]} returned invalid JSON") from None
    if value is None and args[1] == "serve":
        return {}
    if not isinstance(value, dict):
        raise Refusal(f"{args[0]} returned an unexpected status schema")
    return value


def configs(value, node=True):
    """Include transient listeners and service routes when checking exposure."""
    yield value, node
    for key in ("TCP", "Web", "AllowFunnel", "Foreground", "Services"):
        if key in value and not isinstance(value[key], dict):
            raise Refusal("Unexpected Tailscale Serve schema; refusing cutover")
    for child in value.get("Foreground", {}).values():
        if not isinstance(child, dict):
            raise Refusal("Unexpected foreground Serve schema")
        yield from configs(child, node)
    for child in value.get("Services", {}).values():
        if not isinstance(child, dict):
            raise Refusal("Unexpected service Serve schema")
        yield from configs(child, False)


def port_of(target):
    if not isinstance(target, str):
        raise Refusal("Unexpected Tailscale forwarding target")
    if target.isdecimal():
        return target
    if target.startswith("unix:"):
        return None
    try:
        return str(urlsplit(target if "://" in target else "//" + target).port)
    except ValueError:
        raise Refusal("Invalid Tailscale forwarding target") from None


def route_missing(value):
    entries = list(configs(value))
    public = {host for cfg, _ in entries for host, enabled in cfg.get("AllowFunnel", {}).items() if enabled}
    if any(host.rsplit(":", 1)[-1] == PORT for host in public):
        raise Refusal("Public Funnel on share port 8787; retire the exact route before cutover")
    for cfg, node in entries:
        for host, web in cfg.get("Web", {}).items():
            if node and host.rsplit(":", 1)[-1] == PORT:
                raise Refusal("Foreign Web handler on share port 8787")
            if not isinstance(web, dict) or not isinstance(web.get("Handlers", {}), dict):
                raise Refusal("Unexpected Tailscale Web handler schema")
            for handler in web.get("Handlers", {}).values():
                if not isinstance(handler, dict):
                    raise Refusal("Unexpected Tailscale Web handler schema")
                if host in public and "Proxy" in handler and port_of(handler["Proxy"]) == PORT:
                    raise Refusal("Public Funnel forwards to backend 8787; retire the exact route before cutover")
        for port, handler in cfg.get("TCP", {}).items():
            if not isinstance(handler, dict):
                raise Refusal("Unexpected Tailscale TCP handler schema")
            if any(host.rsplit(":", 1)[-1] == port for host in public):
                if "TCPForward" in handler and port_of(handler["TCPForward"]) == PORT:
                    raise Refusal("Public TCP Funnel forwards to backend 8787")
            if node and port == PORT and (cfg is not value or handler != FORWARD):
                raise Refusal("Foreign or incompatible TCP handler on share port 8787")
    return PORT not in value.get("TCP", {})


def probe_authorization(wait):
    # No Authorization header, token file, proxy environment, redirect following,
    # or POST body. These are read-only rejection probes, never Admission.
    for method, path in (("GET", "health"), ("POST", "share"), ("GET", "shares")):
        for attempt in range(10 if wait else 1):
            result = run(["curl", "--disable", "--silent", "--show-error", "--noproxy", "*", "--max-time", "2",
                          "--request", method, "--write-out", "\n%{http_code}",
                          f"http://127.0.0.1:{PORT}/v1/{path}"])
            if result.returncode == 0:
                break
            if not wait or attempt == 9:
                raise Refusal("Loopback share backend unavailable; private route not published")
            time.sleep(0.2)
        body, _, code = result.stdout.rstrip().rpartition("\n")
        try:
            payload = json.loads(body)
        except ValueError:
            payload = None
        if (code != "401" or not isinstance(payload, dict) or payload.get("schema_version") != 1
                or payload.get("ok") is not False or not isinstance(payload.get("error"), dict)
                or payload["error"].get("code") != "unauthorized"):
            raise Refusal("Share API did not reject an unauthenticated request; private route not published")


def verify_listener(wait):
    """Prove probes reach the supervised process, not another local server."""
    launchctl = os.environ.get("AGENTSTART_INSTALL_LAUNCHCTL", "launchctl")
    target = f"gui/{os.getuid()}/io.arthack.agentbrain.share"
    for attempt in range(10 if wait else 1):
        job = run([launchctl, "print", target])
        pid = re.search(r"^\s*pid = ([1-9][0-9]*)\s*$", job.stdout, re.MULTILINE)
        running = re.search(r"^\s*state = running\s*$", job.stdout, re.MULTILINE)
        if job.returncode == 0 and pid and running:
            sockets = run(["lsof", "-nP", "-a", "-p", pid[1], "-iTCP", "-sTCP:LISTEN", "-Fpn"])
            if sockets.returncode == 0:
                pids = [line[1:] for line in sockets.stdout.splitlines() if line.startswith("p")]
                names = [line[1:] for line in sockets.stdout.splitlines() if line.startswith("n")]
                if pids != [pid[1]] or names != ["127.0.0.1:8787"]:
                    raise Refusal("Share process has a foreign or non-loopback listener; private route not published")
                return
        if not wait or attempt == 9:
            raise Refusal("Owned share process has no proven loopback listener; private route not published")
        time.sleep(0.2)


def converge(mode):
    device = read_json(["tailscale", "status", "--json"])
    before = read_json(["tailscale", "serve", "status", "--json"])
    missing = route_missing(before)
    connected = device.get("BackendState") == "Running"
    if mode == "--preflight":
        print("share ingress: private TCP preflight passed" + ("; tailnet offline" if not connected else ""))
        return
    verify_listener(mode == "--install")
    probe_authorization(mode == "--install")
    if not connected:
        if mode == "--status":
            raise Refusal("Tailnet offline; share device endpoint unavailable")
        print("share ingress: loopback service retained; private route convergence deferred (tailnet offline)")
        return
    if mode == "--status":
        if missing:
            raise Refusal("Private TCP share route missing")
        print("share ingress: private TCP route and unauthenticated API rejection verified")
        return
    # Check again after readiness: never overwrite intervening route changes.
    if read_json(["tailscale", "serve", "status", "--json"]) != before:
        raise Refusal("Serve configuration changed during readiness checks; inspect before retrying")
    if missing:
        result = run(["tailscale", "serve", "--bg", "--tcp=8787", "tcp://127.0.0.1:8787"])
        if result.returncode:
            raise Refusal("Private TCP publication failed; inspect Serve state before retrying")
    after = read_json(["tailscale", "serve", "status", "--json"])
    expected = json.loads(json.dumps(before))
    expected.setdefault("TCP", {})[PORT] = FORWARD
    if route_missing(after) or after != expected:
        raise Refusal("Serve postcondition failed or unrelated routes changed; inspect before retrying")
    print("share ingress: private TCP route verified; unrelated routes preserved" + (" (unchanged)" if not missing else ""))


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("--preflight", "--install", "--status"):
        print("Usage: python3 scripts/agentbrain-network.py --preflight|--install|--status", file=sys.stderr)
        sys.exit(64)
    try:
        converge(sys.argv[1])
    except Refusal as error:
        print(f"AgentStart share network: {error}", file=sys.stderr)
        sys.exit(1)
