import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { inspect, merge, projectRoot } from "../scripts/codex-invocation";

const helper = resolve(import.meta.dir, "../scripts/codex-invocation");
let root: string, codexHome: string, source: string, binary: string, cwd: string;
const children: ReturnType<typeof Bun.spawn>[] = [];
const base = 'model="ambient"\n[projects."/previous"]\ntrust_level="untrusted"\n';
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "agentstart-codex-test-"));
  codexHome = join(root, "codex"); mkdirSync(codexHome);
  cwd = join(root, 'work.tree with "quotes"'); mkdirSync(cwd);
  mkdirSync(join(cwd, ".git"));
  source = join(root, "authored.toml");
  writeFileSync(source, '# authored comments remain intact\nmodel="personal"\n[features]\nhooks=true\n');
  writeFileSync(join(codexHome, "config.toml"), base);
  binary = join(root, "native-codex");
  writeFileSync(binary, `#!/usr/bin/python3
import json,os,pathlib,signal,sys,time
args=sys.argv[1:]
profile=pathlib.Path(os.environ['CODEX_HOME'])/(args[1]+'.config.toml') if args[:1]==['--profile'] else None
print(json.dumps({'args':args,'home':os.environ['CODEX_HOME'],'profile':profile.read_text() if profile else None,'mode':(profile.stat().st_mode & 0o777) if profile else None,'pid':os.getpid()}),flush=True)
if os.environ.get('PROBE_WAIT'):
 signal.signal(signal.SIGTERM,lambda *_:sys.exit(143))
 signal.signal(signal.SIGHUP,lambda *_:sys.exit(129))
 while True: signal.pause()
if os.environ.get('PROBE_STDIN'): print(sys.stdin.read(),end='',flush=True)
sys.exit(int(os.environ.get('PROBE_EXIT','0')))
`, { mode: 0o755 });
});
afterEach(async () => {
  for (const child of children.splice(0)) {
    if (child.exitCode === null) child.kill("SIGTERM");
    await child.exited;
  }
  rmSync(root, { recursive: true, force: true });
});
function launch(args: string[] = [], extra: Record<string, string> = {}, native = binary) {
  const child = Bun.spawn([process.execPath, helper, native, ...args], {
    cwd, env: { ...process.env, CODEX_HOME: codexHome, AGENTSTART_CODEX_CONFIG_SOURCE: source, ...extra },
    stdin: "pipe", stdout: "pipe", stderr: "pipe",
  });
  children.push(child); return child;
}
async function result(args: string[] = [], extra: Record<string, string> = {}, native = binary) {
  const child = launch(args, extra, native); child.stdin.end();
  const [code, stdout, stderr] = await Promise.all([child.exited, new Response(child.stdout).text(), new Response(child.stderr).text()]);
  return { code, stdout, stderr, data: stdout ? JSON.parse(stdout.split("\n")[0]) : null };
}
const profiles = () => readdirSync(codexHome).filter(f => f.startsWith("agentstart-invocation-"));

test("native parsing preserves values, delimiter, subcommands, and CLI overrides", () => {
  const args = ["-c", 'model="login"', "exec", "resume", "session", "help", "--cd=../work", "-pchosen", "--", "--cd", "elsewhere"];
  const parsed = inspect(args);
  expect(parsed.bypass).toBe(false);
  expect(parsed.cd).toBe("../work");
  expect(parsed.profile).toBe("chosen");
  expect(parsed.args).toEqual(args.filter(a => a !== "-pchosen"));
  expect(inspect(["-m", "login", "hello"]).bypass).toBe(false);
  expect(inspect(["exec", "help"]).bypass).toBe(true);
  expect(inspect(["--remote=unix://", "resume", "id"]).bypass).toBe(true);
  expect(inspect(["exec", "--ignore-user-config"]).bypass).toBe(true);
  expect(inspect(["exec", "--", "--help"]).bypass).toBe(false);
  for (const args of [["login"], ["app-server", "--stdio"], ["mcp", "list"], ["--help"], ["exec", "--version"]]) {
    expect(inspect(args).bypass).toBe(true);
  }
});

test("private profile trusts effective --cd and worktree root without changing source/base", async () => {
  const authored = readFileSync(source, "utf8");
  const nested = join(cwd, "subdir"); mkdirSync(nested);
  const r = await result(["exec", "-Csubdir", "-m", "cli-model", "a prompt"]);
  expect(r.code).toBe(0);
  expect(r.data.args.slice(2)).toEqual(["exec", "-Csubdir", "-m", "cli-model", "a prompt"]);
  const config = Bun.TOML.parse(r.data.profile);
  expect(config.model).toBe("personal");
  expect(config.projects).toEqual({ [nested]: { trust_level: "trusted" }, [cwd]: { trust_level: "trusted" } });
  expect(r.data.mode).toBe(0o600);
  expect(r.data.home).toBe(codexHome);
  expect(readFileSync(source, "utf8")).toBe(authored);
  expect(readFileSync(join(codexHome, "config.toml"), "utf8")).toBe(base);
  expect(profiles()).toEqual([]);
});

test("explicit native profile overlays authored preferences and stays unchanged", async () => {
  const explicit = 'model="explicit"\n[features]\napps=false\n';
  writeFileSync(join(codexHome, "selected.config.toml"), explicit);
  const r = await result(["--profile", "selected", "review", "--base", "main"]);
  expect(r.code).toBe(0);
  const config = Bun.TOML.parse(r.data.profile);
  expect(config.model).toBe("explicit");
  expect(config.features).toEqual({ apps: false, hooks: true });
  expect(readFileSync(join(codexHome, "selected.config.toml"), "utf8")).toBe(explicit);
  expect(r.data.args.slice(2)).toEqual(["review", "--base", "main"]);
  expect(merge({ values: [1, 2] }, { values: [3] })).toEqual({ values: [3] });
});

test("utility arguments pass through even with an invalid source", async () => {
  writeFileSync(source, "not valid TOML");
  const args = ["-p", "original", "mcp", "list", "--json"];
  const r = await result(args);
  expect(r.code).toBe(0); expect(r.data.args).toEqual(args); expect(r.data.profile).toBeNull();
  expect(profiles()).toEqual([]);
});

test("missing explicit source, malformed TOML, reserved state and invalid cwd fail before launch", async () => {
  expect((await result([], { AGENTSTART_CODEX_CONFIG_SOURCE: join(root, "missing") })).code).toBe(1);
  writeFileSync(source, "model = [");
  expect((await result()).data).toBeNull();
  writeFileSync(source, '[projects."/something"]\ntrust_level="trusted"\n');
  expect((await result()).stderr).toContain("projects is runtime state");
  writeFileSync(source, 'model="ok"\n');
  expect((await result(["--cd", "missing"])).code).toBe(1);
  expect((await result(["-p", "../../escape"])).code).toBe(1);
  expect(profiles()).toEqual([]);
});

test("symlinks resolve to physical cwd; Git worktrees and custom root markers work", async () => {
  rmSync(join(cwd, ".git"), { recursive: true });
  writeFileSync(join(cwd, ".git"), "gitdir: /elsewhere\n");
  const nested = join(cwd, "nested"); mkdirSync(nested);
  const link = join(root, "link"); symlinkSync(nested, link);
  const r = await result(["--cd", link]);
  expect(Object.keys(Bun.TOML.parse(r.data.profile).projects)).toEqual(expect.arrayContaining([nested, cwd]));
  expect(projectRoot(nested, [])).toBe(nested);
  mkdirSync(join(cwd, ".hg"));
  expect(projectRoot(nested, [".hg"])).toBe(cwd);
});

test("concurrent invocations isolate profiles and forward parent termination with cleanup", async () => {
  const first = launch([], { PROBE_WAIT: "1" });
  // Read one complete readiness line from each live child without polling.
  const readLine = async (child: ReturnType<typeof launch>) => {
    const reader = child.stdout.getReader(); let text = "";
    while (!text.includes("\n")) {
      const { value, done } = await reader.read(); if (done) throw new Error("child exited before ready");
      text += new TextDecoder().decode(value);
    }
    reader.releaseLock(); return JSON.parse(text.split("\n")[0]);
  };
  const a = await readLine(first);
  writeFileSync(source, 'model="second"\n');
  const second = launch([], { PROBE_WAIT: "1" }); const b = await readLine(second);
  expect(a.args[1]).not.toBe(b.args[1]);
  expect(Bun.TOML.parse(a.profile).model).toBe("personal");
  expect(Bun.TOML.parse(b.profile).model).toBe("second");
  expect(profiles()).toHaveLength(2);
  first.kill("SIGTERM"); expect(await first.exited).toBe(143);
  expect(profiles()).toHaveLength(1);
  second.kill("SIGHUP"); expect(await second.exited).toBe(129);
  expect(profiles()).toEqual([]);
  expect(() => process.kill(a.pid, 0)).toThrow(); expect(() => process.kill(b.pid, 0)).toThrow();
});

test("native exit status and spawn failures clean up; stdin remains native input", async () => {
  expect((await result([], { PROBE_EXIT: "42" })).code).toBe(42);
  expect((await result([], {}, join(root, "no-binary"))).code).toBe(1);
  expect(profiles()).toEqual([]);
  const child = launch(["exec", "-"], { PROBE_STDIN: "1" });
  child.stdin.write("piped prompt\n"); child.stdin.end();
  expect(await new Response(child.stdout).text()).toEndWith("piped prompt\n");
  expect(await child.exited).toBe(0); expect(profiles()).toEqual([]);
});

test("installed shim balances once, then applies the profile; explicit bypass remains native", async () => {
  const bin = join(root, "bin"); mkdirSync(bin);
  const scripts = {
    uname: "#!/bin/bash\nprintf 'Darwin\\n'\n",
    id: "#!/bin/bash\nprintf '501\\n'\n",
    agentlaunch: '#!/bin/bash\n[ "$1" = --x-harness ] && [ "$2" = codex ] || exit 91\nshift 2\nexport AGENTLAUNCH_LAUNCH=1\nexec codex "$@"\n',
  };
  for (const [name, body] of Object.entries(scripts)) writeFileSync(join(bin, name), body, { mode: 0o755 });
  symlinkSync(binary, join(bin, "codex"));
  const shimDir = join(root, ".local/share/agentlaunch/shims");
  const env = { ...process.env, HOME: root, CODEX_HOME: codexHome,
    AGENTSTART_CODEX_CONFIG_SOURCE: source, AGENTLAUNCH_LAUNCH: "", AGENTLAUNCH_SHIM_BYPASS: "",
    PATH: `${shimDir}:${bin}:${dirname(process.execPath)}:/usr/bin:/bin`,
  };
  const installer = Bun.spawn([resolve(import.meta.dir, "../scripts/install-agentlaunch-shims")], { env, stdout: "pipe", stderr: "pipe" });
  expect(await installer.exited).toBe(0);
  const runShim = async (bypass: string) => {
    const child = Bun.spawn([join(shimDir, "codex"), "exec", "test prompt"], {
      cwd, env: { ...env, AGENTLAUNCH_SHIM_BYPASS: bypass }, stdout: "pipe", stderr: "pipe",
    });
    children.push(child);
    const text = await new Response(child.stdout).text();
    expect(await child.exited).toBe(0); return JSON.parse(text);
  };
  const managed = await runShim(""); expect(Bun.TOML.parse(managed.profile).model).toBe("personal");
  expect(managed.args.slice(2)).toEqual(["exec", "test prompt"]);
  const native = await runShim("1"); expect(native.profile).toBeNull();
  expect(native.args).toEqual(["exec", "test prompt"]);
  expect(profiles()).toEqual([]);
});
