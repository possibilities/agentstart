"""Toolset-scoped HTTP transport for AgentStart's shared stdio MCP inventory."""

import argparse
from contextlib import AsyncExitStack, asynccontextmanager
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
from urllib.parse import urlsplit
from weakref import WeakValueDictionary

from fastmcp import FastMCP
from fastmcp.client.transports import StdioTransport
from fastmcp.server.auth import AccessToken, TokenVerifier
from fastmcp.server.middleware import Middleware
from fastmcp.server.providers.proxy import FastMCPProxy, StatefulProxyClient
from fastmcp.server.transforms import Visibility
from mcp.shared.exceptions import MCPError
from starlette.applications import Starlette
from starlette.routing import Route
import uvicorn
import anyio

NAME = re.compile(r"[a-z][a-z0-9_-]{0,63}")


def private_json(path):
    """Refuse shared, linked, or foreign configuration and credential files."""
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_nlink != 1 or info.st_mode & 0o077):
        raise ValueError(f"expected a private account-owned file: {path}")
    return json.loads(path.read_text())


def absolute_path(value):
    if not isinstance(value, str) or not Path(value).is_absolute():
        raise ValueError("configuration paths must be absolute")
    return Path(value)


class GatewayTokenVerifier(TokenVerifier):
    """Each endpoint accepts only its own high-entropy bearer credential."""

    def __init__(self, toolset, digest):
        super().__init__(required_scopes=[toolset])
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise ValueError("invalid gateway credential digest")
        self.digest, self.toolset = digest, toolset

    async def verify_token(self, token):
        candidate = hashlib.sha256(token.encode()).hexdigest()
        if not hmac.compare_digest(candidate, self.digest):
            return None
        return AccessToken(token=token, client_id=self.toolset, scopes=[self.toolset])


class StdioSessionClient(StatefulProxyClient):
    """Retain the library lifecycle with a distinct transport per frontend."""

    def new(self):
        client = super().new()
        client.transport = StdioTransport(
            command=self.transport.command, args=self.transport.args, keep_alive=False,
        )
        return client


class RequireSession(Middleware):
    """Negotiate the session protocol needed by the fleet's stateful servers.

    MCP's sessionless protocol cannot retain a stdio REPL or relay approvals.
    Modern auto clients fall back to initialize when discover is unsupported.
    """

    def __init__(self):
        # Requests hold strong references only while queued/running; idle sessions
        # do not accumulate a second lifecycle registry beside FastMCP's own.
        self._locks = WeakValueDictionary()

    async def on_request(self, context, call_next):
        if context.method == "server/discover":
            raise MCPError(code=-32601, message="Use initialize: this gateway requires MCP sessions")
        if context.method == "initialize":
            return await call_next(context)
        session_id = context.fastmcp_context.session_id
        if not session_id:
            raise MCPError(code=-32600, message="An initialized MCP session is required")
        lock = self._locks.get(session_id)
        if lock is None:
            lock = anyio.Lock()
            self._locks[session_id] = lock
        # Proxy metadata discovery also restores callback context. Serialize the
        # complete frontend request, before either metadata or tool forwarding.
        # Protocol cancellation and callback replies are not server requests.
        async with lock:
            return await call_next(context)


def validate(config):
    if (not isinstance(config, dict) or set(config) != {
            "version", "resources", "port", "public_origin", "session_idle_seconds", "toolsets"
    } or config["version"] != 1):
        raise ValueError("invalid gateway configuration")
    if type(config["port"]) is not int or not 1024 <= config["port"] <= 65535:
        raise ValueError("gateway port must be between 1024 and 65535")
    idle = config["session_idle_seconds"]
    if type(idle) is not int or not 30 <= idle <= 86400:
        raise ValueError("session_idle_seconds must be between 30 and 86400")
    origin = urlsplit(config["public_origin"])
    if (origin.scheme != "https" or not origin.hostname or origin.port not in (None, 443)
            or origin.username or origin.password or origin.path or origin.query or origin.fragment):
        raise ValueError("public_origin must be an HTTPS origin without a path")
    resources = private_json(absolute_path(config["resources"]))
    if set(resources) != {"mcpServers"} or not isinstance(resources["mcpServers"], dict):
        raise ValueError("invalid MCP inventory")
    servers = resources["mcpServers"]
    for name, server in servers.items():
        if (not NAME.fullmatch(name) or not isinstance(server, dict)
                or set(server) != {"command", "args"}
                or not isinstance(server["command"], str) or not server["command"]
                or not isinstance(server["args"], list)
                or not all(isinstance(arg, str) for arg in server["args"])
                or any("\0" in arg for arg in [server["command"], *server["args"]])):
            raise ValueError(f"invalid stdio server configuration: {name}")
    if not isinstance(config["toolsets"], dict) or not config["toolsets"]:
        raise ValueError("at least one named toolset is required")
    digests = set()
    for name, toolset in config["toolsets"].items():
        if (not NAME.fullmatch(name) or not isinstance(toolset, dict)
                or set(toolset) != {"credential", "tools"}
                or not isinstance(toolset["tools"], dict) or not toolset["tools"]):
            raise ValueError(f"invalid toolset: {name}")
        for server, names in toolset["tools"].items():
            if (server not in servers or not isinstance(names, list) or not names
                    or not all(isinstance(tool, str) and tool for tool in names)
                    or len(set(names)) != len(names) or ("*" in names and names != ["*"])):
                raise ValueError(f"invalid tool selection: {name}/{server}")
        credential = private_json(absolute_path(toolset["credential"]))
        if set(credential) != {"version", "sha256"} or credential["version"] != 1:
            raise ValueError(f"invalid credential: {name}")
        verifier = GatewayTokenVerifier(name, credential["sha256"])
        if verifier.digest in digests:
            raise ValueError("toolsets must have different credentials")
        digests.add(verifier.digest)
    return servers


def build_gateway(config):
    servers = validate(config)
    apps, clients, routes = [], [], []
    for name, toolset in config["toolsets"].items():
        credential = private_json(Path(toolset["credential"]))
        gateway = FastMCP(
            f"AgentStart {name}",
            instructions=(
                "Tools are prefixed with their source server name. Use each server's guide "
                "and workflow skill. Calls run on the Mac; identify accounts and sessions "
                "explicitly. A returned Mac path is not an attached file."
            ),
            auth=GatewayTokenVerifier(name, credential["sha256"]),
            middleware=[RequireSession()],
        )
        # A broken backend must not silently produce an incomplete catalog.
        gateway.provider_error_strategy = "raise"
        for server_name, names in toolset["tools"].items():
            server = servers[server_name]
            client = StdioSessionClient(
                StdioTransport(command=server["command"], args=server["args"]),
                init_timeout=30,
            )
            clients.append(client)
            proxy = FastMCPProxy(client_factory=client.new_stateful)
            proxy.provider_error_strategy = "raise"
            # Visibility applies to both list and lookup/call. A toolset does
            # not implicitly grant the backend's prompts or resources.
            proxy.add_transform(Visibility(False, match_all=True))
            proxy.add_transform(Visibility(
                True, components={"tool"}, names=None if names == ["*"] else set(names),
            ))
            gateway.mount(proxy, namespace=server_name)
        path = f"/mcp/{name}"
        child = gateway.http_app(
            path=path, stateless_http=False, session_idle_timeout=config["session_idle_seconds"],
            host_origin_protection=True,
            allowed_hosts=["127.0.0.1:*", "localhost:*", urlsplit(config["public_origin"]).hostname],
            allowed_origins=[config["public_origin"]],
        )
        apps.append(child)
        # Exact routes avoid redirects and leave /mcp and unknown toolsets closed.
        routes.append(Route(path, endpoint=child))

    @asynccontextmanager
    async def lifespan(_app):
        try:
            async with AsyncExitStack() as stack:
                for child in apps:
                    await stack.enter_async_context(child.router.lifespan_context(child))
                yield
        finally:
            # StatefulProxyClient also reaps children on each HTTP session close.
            for client in clients:
                await client.clear()

    return Starlette(routes=routes, lifespan=lifespan)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    config = private_json(args.config)
    app = build_gateway(config)
    if args.check:
        print("Gateway configuration is valid")
        return
    uvicorn.run(app, host="127.0.0.1", port=config["port"], log_level="warning", access_log=False)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"AgentStart MCP gateway: {error}") from error
