import assert from "node:assert/strict";
import { homedir } from "node:os";
import { join } from "node:path";

type Settings = { version: 1; endpoint: string; port: number };
type Serve = {
  TCP?: Record<string, unknown>;
  Web?: Record<string, { Handlers?: Record<string, unknown> }>;
  AllowFunnel?: Record<string, boolean>;
};
export function routePlan(settings: Settings, dnsName: string, status: Serve) {
  const url = new URL(settings.endpoint);
  const port = Number(url.port || 443);
  if (settings.version !== 1 || url.protocol !== "wss:" || url.hostname !== dnsName || url.pathname !== "/v2/client" || url.search || url.hash || url.username || url.password || !Number.isInteger(port) || port < 1024 || port > 65535 || !Number.isInteger(settings.port) || settings.port < 1024 || settings.port > 65535)
    throw new Error("AgentVoice requires a dedicated high-port WSS endpoint on this Tailscale device");
  const host = url.host;
  const proxy = `http://127.0.0.1:${settings.port}`;
  if (status.AllowFunnel?.[host]) throw new Error("Refusing a public Funnel endpoint for AgentVoice");
  const web = status.Web?.[host];
  const tcp = status.TCP?.[String(port)];
  if (web || tcp) {
    assert.deepEqual(tcp, { HTTPS: true }, "Dedicated port has foreign TCP configuration");
    assert.deepEqual(web, { Handlers: { "/": { Proxy: proxy } } }, "Dedicated port has foreign handlers");
  }
  return { host, port, proxy, install: !web };
}

export function preservedRoutes(before: Serve, after: Serve, host: string, port: number) {
  const without = (value: Serve) => {
    const copy = structuredClone(value);
    delete copy.TCP?.[String(port)];
    delete copy.Web?.[host];
    // Empty collections are omitted by Tailscale.
    for (const key of ["TCP", "Web", "AllowFunnel"] as const)
      if (copy[key] && Object.keys(copy[key]).length === 0) delete copy[key];
    return copy;
  };
  assert.deepEqual(without(after), without(before), "Unrelated Tailscale routes changed; inspect before continuing");
}

async function run(argv: string[]): Promise<string> {
  const child = Bun.spawn(argv, { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  const timer = setTimeout(() => child.kill(), 15000);
  try {
    const [code, output] = await Promise.all([child.exited, new Response(child.stdout).text(), new Response(child.stderr).text()]);
    if (code !== 0) throw new Error(`${argv[0]} ${argv[1]} failed; inspect that tool's status`);
    return output;
  } finally { clearTimeout(timer); }
}

export async function converge(enable: boolean) {
  const command = join(homedir(), ".local/bin/agentvoice");
  if (!Bun.which(command)) {
    if (enable) throw new Error("Install AgentVoice first");
    return;
  }
  const voice = (...args: string[]) => run([command, ...args]);
  let settings = JSON.parse(await voice("network", "status")) as Settings | null;
  if (!settings && !enable) return;
  const device = JSON.parse(await run(["tailscale", "status", "--json"]));
  const dnsName = device.Self?.DNSName?.replace(/\.$/, "");
  if (device.BackendState !== "Running" || typeof dnsName !== "string" || !/^[a-zA-Z0-9.-]+$/.test(dnsName))
    throw new Error("Tailscale must be connected with an assigned DNS name");
  const proposed: Settings = settings ?? { version: 1, endpoint: `wss://${dnsName}:48414/v2/client`, port: 44414 };
  const before = JSON.parse(await run(["tailscale", "serve", "status", "--json"])) as Serve;
  const plan = routePlan(proposed, dnsName, before);
  if (!settings) {
    await voice("network", "configure", "--endpoint", proposed.endpoint, "--port", String(proposed.port));
    settings = proposed;
    // Restart only at first enable; ordinary installer already converges the server.
    await voice("service", "restart");
  }
  if (plan.install) await run(["tailscale", "serve", "--bg", `--https=${plan.port}`, plan.proxy]);
  const after = JSON.parse(await run(["tailscale", "serve", "status", "--json"])) as Serve;
  assert.equal(routePlan(settings, dnsName, after).install, false, "Dedicated route was not installed");
  preservedRoutes(before, after, plan.host, plan.port);
  console.log("AgentVoice tailnet-only WSS route verified; unrelated routes and Funnel preserved.");
}
if (import.meta.main) {
  const args = process.argv.slice(2);
  if (args.length !== 1 || !["--install", "--enable"].includes(args[0]!)) {
    console.error("Usage: bun scripts/agentvoice-network.ts --install|--enable");
    process.exitCode = 64;
  } else {
    try { await converge(args[0] === "--enable"); }
    catch (error) { console.error(error instanceof Error ? error.message : "Network convergence failed"); process.exitCode = 1; }
  }
}
