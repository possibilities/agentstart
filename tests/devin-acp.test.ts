import { afterEach, beforeEach, expect, test } from "bun:test";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { invocationRecords, type Invocation } from "../scripts/devin-invocation.ts";
import { cleanupDevinInvocations } from "../scripts/devin-cleanup.ts";
import { processIdentity } from "../scripts/devin-process.ts";

// Authoring gate: the public stdio boundary owns protocol byte preservation,
// session-cwd preparation-before-admission, and native-process reference lifetime.
// Terminal/helper tests cannot detect a proxy forwarding too early, polluting
// stdout, snapshotting startup cwd, or leaving its owned ACP child alive.
const entry = resolve(import.meta.dir, "../scripts/devin-invocation.ts");
let root: string, home: string, resources: string, state: string, native: string, repo: string;
const children: ReturnType<typeof Bun.spawn>[] = [];
function write(path: string, body: string) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, body); }
function gitRepo(path: string) {
  mkdirSync(path, { recursive: true });
  const result = Bun.spawnSync(["git", "init", "-b", "main", path], { stdout: "pipe", stderr: "pipe" });
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
}
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "agentstart-acp-test-")); home = join(root, "home");
  resources = join(root, "resources"); state = join(home, ".local/state/agentstart/devin-invocations");
  native = join(root, "native-devin"); repo = join(root, "repo");
  mkdirSync(join(home, "code"), { recursive: true }); gitRepo(repo);
  write(join(resources, "roles/default/APPEND_SYSTEM_PROMPT.md"), "Manual test guidance.\n");
  write(join(resources, "roles/default/mcp.json"), JSON.stringify({ mcpServers: { example: { command: "${HOME}/bin/example", args: ["mcp"] } } }));
  write(join(resources, "roles/default/skills/review/SKILL.md"), "Review test changes.\n");
  write(native, `#!${process.execPath}
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
writeFileSync(process.env.FAKE_PID, String(process.pid));
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, () => {
  writeFileSync(process.env.FAKE_SIGNAL, signal); if (!process.env.FAKE_IGNORE_SIGNALS) process.exit(0);
});
if (process.argv.slice(2).some(arg => ['--help', '--cloud', 'auth'].includes(arg))) {
  process.stdout.write('native bypass\\n'); process.exit(0);
}
if (process.env.FAKE_HELLO) {
  const hello = process.env.FAKE_HELLO;
  if (process.env.FAKE_SPLIT_HELLO) {
    const at = Math.floor(hello.length / 2);
    process.stdout.write(hello.slice(0, at));
    writeFileSync(process.env.FAKE_PARTIAL, 'ready');
    setTimeout(() => process.stdout.write(hello.slice(at)), 100);
  } else process.stdout.write(hello);
}
let buffer = '';
for await (const chunk of Bun.stdin.stream()) {
  buffer += Buffer.from(chunk).toString();
  let at;
  while ((at = buffer.indexOf('\\n')) >= 0) {
    const frame = buffer.slice(0, at + 1); buffer = buffer.slice(at + 1);
    appendFileSync(process.env.FAKE_RECEIVED, frame);
    const rpc = JSON.parse(frame);
    if (rpc.method === 'session/new' || rpc.method === 'session/load') {
      const target = join(execFileSync('git', ['-C', rpc.params.cwd, 'rev-parse', '--show-toplevel'], {encoding:'utf8'}).trim(), '.devin');
      const ready = existsSync(join(target, 'skills/review/SKILL.md')) && existsSync(join(target, 'skills/prime/SKILL.md'));
      const mcp = existsSync(join(target, 'mcp_config.local.json')) ? JSON.parse(readFileSync(join(target, 'mcp_config.local.json'), 'utf8')) : null;
      process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:rpc.id,result:{ready,mcp,cwd:rpc.params.cwd,startup:process.cwd(),pid:process.pid}}) + '\\n');
    } else process.stdout.write(frame);
  }
}
if (process.env.FAKE_IGNORE_EOF) { setInterval(() => {}, 1000); await new Promise(() => {}); }
`);
  Bun.spawnSync(["chmod", "+x", native]);
});
afterEach(async () => {
  for (const child of children.splice(0)) if (child.exitCode === null) { child.kill("SIGKILL"); await child.exited; }
  if (existsSync(join(root, "pid"))) {
    const pid = Number(readFileSync(join(root, "pid"), "utf8"));
    if (processIdentity(pid)) { try { process.kill(pid, "SIGKILL"); } catch {} }
  }
  rmSync(root, { recursive: true, force: true });
});

async function bounded<T>(promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  try { return await Promise.race([promise, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("ACP fixture timed out")), 4000); })]); }
  finally { clearTimeout(timer!); }
}
async function waitFor(predicate: () => boolean) {
  await bounded((async () => { while (!predicate()) await Bun.sleep(10); })());
}
function launch(extraEnv: Record<string, string> = {}, args = ["acp"], publicCommand?: string) {
  const child = Bun.spawn(publicCommand ? [publicCommand, ...args] : [process.execPath, entry, "--native", native, "--", ...args], {
    cwd: join(home, "code"), env: { ...process.env, HOME: home, AGENTSTART_RESOURCES_ROOT: resources,
      AGENTSTART_DEVIN_ACP_ROLE: "1", FAKE_RECEIVED: join(root, "received"), FAKE_PID: join(root, "pid"),
      FAKE_SIGNAL: join(root, "signal"), ...extraEnv }, stdin: "pipe", stdout: "pipe", stderr: "pipe",
  });
  children.push(child);
  const reader = child.stdout.getReader(); let buffer = "";
  async function line() {
    return bounded((async () => {
      while (!buffer.includes("\n")) {
        const chunk = await reader.read();
        if (chunk.done) throw new Error(`proxy ended: ${await new Response(child.stderr).text()}`);
        buffer += Buffer.from(chunk.value).toString();
      }
      const at = buffer.indexOf("\n"), result = buffer.slice(0, at + 1); buffer = buffer.slice(at + 1); return result;
    })());
  }
  const send = (frame: string) => { child.stdin.write(frame); child.stdin.flush(); };
  const request = (id: string | number, cwd: unknown, method = "session/new") => send(JSON.stringify({ jsonrpc: "2.0", id, method, params: { cwd, mcpServers: [], model: "native-choice" } }) + "\n");
  async function rest() {
    let result = buffer; buffer = "";
    while (true) { const chunk = await reader.read(); if (chunk.done) return result; result += Buffer.from(chunk.value).toString(); }
  }
  return { child, line, send, request, rest };
}

test("opted-in ACP prepares each session cwd before native admission and preserves all other bytes", async () => {
  const hello = ' { "jsonrpc": "2.0", "id": 77, "method": "session/request_permission", "params": {"options": ["ask"]} }\r\n';
  const f = launch({ FAKE_HELLO: hello });
  expect(await f.line()).toBe(hello);
  const unchanged = ' {"jsonrpc":"2.0", "id":77, "result":{"outcome":{"optionId":"deny"}}, "unknown": true }\r\n';
  f.send(unchanged); expect(await f.line()).toBe(unchanged);
  const extension = '{ "jsonrpc": "2.0", "method": "extension/custom", "params": {"prompt":"no /prime injection"} }\n';
  f.send(extension); expect(await f.line()).toBe(extension);
  const second = join(root, "other repo"); gitRepo(second);
  const subdir = join(repo, "nested"); mkdirSync(subdir);
  write(join(second, ".devin/config.json"), "project configuration\n");
  for (const [id, cwd, method] of [["one", repo, "session/new"], [2, second, "session/load"], [3, subdir, "session/new"]] as const) {
    f.request(id, cwd, method);
    const response = JSON.parse(await f.line());
    expect(response.id).toBe(id); expect(response.result.ready).toBe(true);
    expect(response.result.cwd).toBe(cwd); expect(response.result.startup).toBe(realpathSync(join(home, "code")));
    expect(response.result.mcp.mcpServers.example.command).toBe(join(home, "bin/example"));
  }
  expect(existsSync(join(home, "code/.devin"))).toBe(false);
  expect(readFileSync(join(root, "received"), "utf8")).toBe(unchanged + extension +
    [["one", repo, "session/new"], [2, second, "session/load"], [3, subdir, "session/new"]].map(([id, cwd, method]) =>
      JSON.stringify({ jsonrpc: "2.0", id, method, params: { cwd, mcpServers: [], model: "native-choice" } }) + "\n").join(""));
  expect(readFileSync(join(second, ".devin/config.json"), "utf8")).toBe("project configuration\n");
  expect(cleanupDevinInvocations(state)).toBe(0);
  f.child.stdin.end(); await bounded(f.child.exited);
  expect(await new Response(f.child.stderr).text()).toContain("Kept existing .devin/config.json");
  expect(cleanupDevinInvocations(state)).toBe(2);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
  expect(readFileSync(join(second, ".devin/config.json"), "utf8")).toBe("project configuration\n");
});

test("malformed admissions and snapshot failures return exact-id RPC errors without native admission", async () => {
  const f = launch();
  for (const [id, cwd] of [["relative", "relative"], [10, join(root, "absent")], [11, home], [12, null]] as const) {
    f.request(id, cwd);
    expect(JSON.parse(await f.line())).toEqual({ jsonrpc: "2.0", id, error: { code: -32602, message: "cwd must be an absolute existing directory in a Git repository" } });
  }
  f.send('{not json}\n');
  expect(JSON.parse(await f.line())).toEqual({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  f.send(JSON.stringify({ jsonrpc: "2.0", method: "session/new", params: { cwd: repo } }) + "\n");
  expect(JSON.parse(await f.line()).error.code).toBe(-32600);
  write(join(repo, ".devin/agentstart-owner.json"), '{"owner":"foreign"}');
  f.request("foreign", repo, "session/load");
  expect(JSON.parse(await f.line())).toEqual({ jsonrpc: "2.0", id: "foreign", error: { code: -32000, message: "AgentStart Devin Role snapshot preparation failed" } });
  expect(existsSync(join(root, "received"))).toBe(false);
  expect(readFileSync(join(repo, ".devin/agentstart-owner.json"), "utf8")).toBe('{"owner":"foreign"}');
  const valid = join(root, "valid"); gitRepo(valid);
  f.request(13, valid); expect(JSON.parse(await f.line()).result.ready).toBe(true);
  const received = readFileSync(join(root, "received"), "utf8");
  write(join(valid, ".devin/agentstart-owner.json"), "human changed the marker");
  f.request(14, valid);
  expect(JSON.parse(await f.line()).error.code).toBe(-32000);
  expect(readFileSync(join(root, "received"), "utf8")).toBe(received);
  f.child.stdin.end(); await bounded(f.child.exited);
});

test("a blocked snapshot admission does not block an unrelated native RPC", async () => {
  mkdirSync(state, { recursive: true });
  const locker = Bun.spawn([process.execPath, "-e", `
    import { lockDevinRoot } from ${JSON.stringify(resolve(import.meta.dir, "../scripts/devin-root-lock.ts"))};
    import { writeFileSync } from 'node:fs';
    const release = lockDevinRoot(${JSON.stringify(state)}, ${JSON.stringify(realpathSync(repo))});
    writeFileSync(${JSON.stringify(join(root, "locked"))}, 'ready');
    process.on('SIGTERM', () => { release(); process.exit(0); });
    setInterval(() => {}, 1000);
  `], { stdout: "pipe", stderr: "pipe" }); children.push(locker);
  await waitFor(() => existsSync(join(root, "locked")));
  const f = launch(); f.request(1, repo);
  // Native admission is waiting in the helper's per-root lock.
  const ping = '{"jsonrpc":"2.0","id":2,"method":"extension/ping"}\n';
  f.send(ping); expect(await f.line()).toBe(ping);
  expect(readFileSync(join(root, "received"), "utf8")).toBe(ping);
  // The worker is still locked, so fill the bounded admission queue. Excess
  // requests are rejected independently rather than growing retained frames.
  for (let id = 3; id <= 34; id++) f.request(id, repo);
  expect(JSON.parse(await f.line())).toEqual({ jsonrpc: "2.0", id: 34, error: { code: -32000, message: "AgentStart Devin Role admission capacity exceeded" } });
  f.child.stdin.end(); await bounded(f.child.exited);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
  locker.kill("SIGTERM"); await bounded(locker.exited);
});

test("overlapping ACP wrappers share snapshots and both process identities protect cleanup", async () => {
  const first = launch(), second = launch({ FAKE_IGNORE_EOF: "1" });
  first.request(1, repo); const one = JSON.parse(await first.line());
  second.request(2, repo); const two = JSON.parse(await second.line());
  const records = invocationRecords(state, realpathSync(repo)).map(path => JSON.parse(readFileSync(path, "utf8")) as Invocation);
  expect(records).toHaveLength(2); expect(records[0]!.snapshot).toBe(records[1]!.snapshot);
  expect(new Set(records.map(record => record.wrapper.pid))).toEqual(new Set([first.child.pid, second.child.pid]));
  expect(new Set(records.map(record => record.child!.pid))).toEqual(new Set([one.result.pid, two.result.pid]));
  first.child.stdin.end(); await bounded(first.child.exited);
  expect(cleanupDevinInvocations(state)).toBe(0);
  // Simulate a killed wrapper without killing native. The recorded native
  // identity, rather than mere wrapper/PID existence, must retain its resources.
  second.child.kill("SIGKILL"); await bounded(second.child.exited);
  expect(cleanupDevinInvocations(state)).toBe(0);
  process.kill(two.result.pid, "SIGTERM");
  await waitFor(() => !processIdentity(two.result.pid));
  expect(cleanupDevinInvocations(state)).toBe(2);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
});

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP", "EOF"] as const) {
  test(`ACP ${signal} forwards shutdown and reaps the owned native process`, async () => {
    const f = launch({ FAKE_IGNORE_EOF: "1" }); f.request(1, repo);
    const pid = JSON.parse(await f.line()).result.pid;
    if (signal === "EOF") f.child.stdin.end(); else f.child.kill(signal);
    await bounded(f.child.exited);
    expect(readFileSync(join(root, "signal"), "utf8")).toBe(signal === "EOF" ? "SIGTERM" : signal);
    expect(processIdentity(pid)).toBeNull();
    expect(cleanupDevinInvocations(state)).toBe(1);
  });
}

test("local errors never splice into a partial native protocol frame", async () => {
  const hello = ' {"jsonrpc":"2.0","method":"session/update","params":{"native":"unchanged"}}\r\n';
  const partial = join(root, "partial");
  const f = launch({ FAKE_HELLO: hello, FAKE_SPLIT_HELLO: "1", FAKE_PARTIAL: partial });
  await waitFor(() => existsSync(partial));
  f.request("invalid", "relative");
  const lines = [await f.line(), await f.line()];
  expect(lines).toContain(hello);
  expect(lines).toContain(JSON.stringify({ jsonrpc: "2.0", id: "invalid", error: { code: -32602, message: "cwd must be an absolute existing directory in a Git repository" } }) + "\n");
  f.child.stdin.end(); await bounded(f.child.exited);
});

test("a native process that ignores shutdown is force-reaped after the grace period", async () => {
  const f = launch({ FAKE_IGNORE_SIGNALS: "1", FAKE_IGNORE_EOF: "1" }); f.request(1, repo);
  const pid = JSON.parse(await f.line()).result.pid;
  f.child.stdin.end(); expect(await bounded(f.child.exited)).toBe(143);
  expect(processIdentity(pid)).toBeNull();
  expect(cleanupDevinInvocations(state)).toBe(1);
});

test("opt-in is exact and default ACP, utilities and cloud/help stay native", async () => {
  for (const [env, args] of [[{ AGENTSTART_DEVIN_ACP_ROLE: "0" }, ["acp"]], [{}, ["acp", "--cloud"]], [{}, ["acp", "--help"]], [{}, ["auth"]]] as const) {
    const f = launch(env, [...args]);
    if (args.length === 1 && args[0] === "acp") {
      f.request(1, repo); expect(JSON.parse(await f.line()).result.ready).toBe(false); f.child.stdin.end();
    } else expect(await f.line()).toBe("native bypass\n");
    expect(await bounded(f.child.exited)).toBe(0);
    expect(existsSync(join(repo, ".devin"))).toBe(false);
  }
  const invalid = launch({ AGENTSTART_DEVIN_ACP_ROLE: "true" });
  expect(await bounded(invalid.child.exited)).toBe(1);
  expect(await new Response(invalid.child.stderr).text()).toContain("must be 0 or 1");
});

test("the installed public Devin shim carries the opt-in and retains its explicit bypass", async () => {
  const vendor = join(home, ".local/share/devin/cli/_versions/current/bin/devin");
  mkdirSync(dirname(vendor), { recursive: true }); copyFileSync(native, vendor); chmodSync(vendor, 0o755);
  const bin = join(home, ".local/bin"), publicDevin = join(bin, "devin"); mkdirSync(bin, { recursive: true }); symlinkSync(vendor, publicDevin);
  for (const tool of ["codexnk", "fxnk"]) {
    const installer = join(home, "workshops", tool, "scripts/install.sh");
    write(installer, "#!/bin/sh\nprintf '%s\\n' /usr/bin/true\n"); chmodSync(installer, 0o755);
  }
  const result = Bun.spawnSync([resolve(import.meta.dir, "../scripts/install-harness-shims")], {
    env: { ...process.env, HOME: home, AGENTSTART_INSTALL_BIN_DIR: bin, AGENTSTART_WORKSHOPS_ROOT: join(home, "workshops") }, stdout: "pipe", stderr: "pipe",
  });
  expect(result.exitCode, result.stderr.toString()).toBe(0);
  const equipped = launch({}, ["acp"], publicDevin); equipped.request(1, repo);
  expect(JSON.parse(await equipped.line()).result.ready).toBe(true);
  equipped.child.stdin.end(); await bounded(equipped.child.exited); expect(cleanupDevinInvocations(state)).toBe(1);
  const bypass = launch({ AGENTSTART_SHIM_BYPASS: "1" }, ["acp"], publicDevin); bypass.request(2, repo);
  expect(JSON.parse(await bypass.line()).result.ready).toBe(false);
  bypass.child.stdin.end(); expect(await bounded(bypass.child.exited)).toBe(0);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
});

test("oversized and truncated frames fail closed and terminate native without protocol diagnostics", async () => {
  for (const frame of ["x".repeat(8 * 1024 * 1024 + 1) + "\n", '{"jsonrpc":"2.0","method":"session/new"']) {
    const f = launch(); f.send(frame); f.child.stdin.end(); expect(await bounded(f.child.exited)).toBe(1);
    expect(await f.rest()).toBe("");
    expect(existsSync(join(root, "received"))).toBe(false);
  }
});
