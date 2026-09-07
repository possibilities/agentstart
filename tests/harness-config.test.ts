import { afterEach, beforeEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { apply, captureEdits, layout, notify, registerNativeHome, resolvePreferences, status, watchConfigs } from "../scripts/harness-config.ts";

let root: string, files: ReturnType<typeof layout>;
const children: ReturnType<typeof Bun.spawn>[] = [];
const cli = resolve(import.meta.dir, "../scripts/agentstart");
function put(path: string, data: string) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, data); }
function prefs(harness: "claude" | "codex", model: string) {
  put(harness === "claude" ? files.claudeStowSource : files.sources.codex,
    harness === "claude" ? JSON.stringify({ model }) : Bun.TOML.stringify({ model }));
}
function environment() { return { ...process.env, HOME: root, XDG_STATE_HOME: join(root, "state"), CODEX_HOME: join(root, ".codex"), CLAUDE_CONFIG_DIR: join(root, ".claude"), AGENTSTART_CODEX_CONFIG_SOURCE: "", AGENTSTART_CLAUDE_CONFIG_SOURCE: "" }; }
function launch(args: string[]) {
  const child = Bun.spawn([process.execPath, cli, ...args], { env: environment(), stdout: "pipe", stderr: "pipe" });
  children.push(child); return child;
}
async function until(check: () => boolean, ms = 5000) {
  const end = Date.now() + ms;
  while (!check()) { if (Date.now() > end) throw new Error("condition timed out"); await Bun.sleep(25); }
}
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "agentstart-config-test-")); files = layout(root, join(root, "state"));
  prefs("claude", "sonnet"); prefs("codex", "gpt-test");
  mkdirSync(dirname(files.sources.claude), { recursive: true }); symlinkSync(files.claudeStowSource, files.sources.claude);
  put(files.native.claude, '{"model":"base", "hooks":{}}'); put(files.native.codex, 'model="base"\n');
});
afterEach(async () => {
  for (const child of children.splice(0)) { if (child.exitCode === null) child.kill(); await child.exited; }
  rmSync(root, { recursive: true, force: true });
});

test("publishes private snapshots, follows semantic edits, and never writes either source or native files", async () => {
  const before = [files.sources.claude, files.sources.codex, ...Object.values(files.native)].map(f => readFileSync(f, "utf8"));
  expect((await apply(files)).notices).toEqual([]);
  expect(resolvePreferences("claude", files)).toContain("snapshots/");
  expect(statSync(resolvePreferences("claude", files)).mode & 0o777).toBe(0o600);
  expect([files.sources.claude, files.sources.codex, ...Object.values(files.native)].map(f => readFileSync(f, "utf8"))).toEqual(before);
  prefs("claude", "opus");
  // A launch need not wait for the watcher debounce.
  expect(resolvePreferences("claude", files)).toBe(files.sources.claude);
  expect((await apply(files)).notices.map(n => n.kind)).toEqual(["applied"]);
  expect(JSON.parse(readFileSync(resolvePreferences("claude", files), "utf8")).model).toBe("opus");
  put(files.claudeStowSource, '{\n  "model": "opus"\n}\n');
  expect((await apply(files)).notices).toEqual([]);
});

test("invalid edits retain last good, deduplicate alerts, and announce recovery", async () => {
  await apply(files); const good = resolvePreferences("codex", files);
  put(files.sources.codex, 'model=[');
  expect((await apply(files)).notices.map(n => n.kind)).toEqual(["attention"]);
  expect(resolvePreferences("codex", files)).toBe(good);
  expect((await apply(files)).notices).toEqual([]);
  prefs("codex", "recovered");
  expect((await apply(files)).notices.map(n => n.kind)).toEqual(["recovered"]);
  expect(readFileSync(resolvePreferences("codex", files), "utf8")).toContain("recovered");
});

test("no-cache invalid input refuses launch; absent optional config remains optional", async () => {
  put(files.sources.codex, 'model=42');
  expect(() => resolvePreferences("codex", files)).toThrow("must be a string");
  unlinkSync(files.sources.codex);
  expect(resolvePreferences("codex", files)).toBe(files.sources.codex);
  expect((await apply(files)).harnesses.codex.status).toBe("not-configured");
});

test("lost source or replaced Stow link is reported without repairing authored files", async () => {
  await apply(files); const good = resolvePreferences("claude", files);
  unlinkSync(files.sources.claude); put(files.sources.claude, '{"model":"independent"}');
  expect((await apply(files)).harnesses.claude.error).toContain("link differs");
  expect(resolvePreferences("claude", files)).toBe(good);
  expect(readFileSync(files.sources.claude, "utf8")).toContain("independent");
  unlinkSync(files.sources.codex);
  expect((await apply(files)).harnesses.codex.error).toContain("missing");
});

test("baseline shadowing stays quiet; deliberate native edits persist until acknowledged or adopted", async () => {
  const first = await apply(files);
  expect(first.harnesses.claude.shadowed).toHaveLength(1); expect(first.notices).toEqual([]);
  put(files.native.claude, '{"model":"private-value", "hooks":{"x":1}}');
  const report = await apply(files);
  expect(report.harnesses.claude.drift).toEqual([{ key: "model", file: files.native.claude }]);
  expect(JSON.stringify(report)).not.toContain("private-value");
  expect((await apply(files)).notices).toEqual([]);
  const before = readFileSync(files.native.claude, "utf8");
  expect((await apply(files, true)).harnesses.claude.drift).toEqual([]);
  expect(readFileSync(files.native.claude, "utf8")).toBe(before);
  put(files.native.claude, '{"model":"adopt-me"}'); await apply(files);
  prefs("claude", "adopt-me");
  expect((await apply(files)).harnesses.claude.drift).toEqual([]);
});

test("trust and generated hook churn stays quiet; alternate account homes are monitored", async () => {
  const alternate = join(root, "accounts/other/settings.json");
  put(alternate, '{"model":"baseline"}'); registerNativeHome("claude", alternate, files);
  await apply(files);
  put(files.native.codex, 'model="base"\n[projects."/new"]\ntrust_level="trusted"');
  put(files.native.claude, '{"model":"base", "hooks":{"generated":true},"statusLine":{}}');
  expect((await apply(files)).notices).toEqual([]);
  put(alternate, '{"model":"changed"}');
  expect((await apply(files)).harnesses.claude.drift).toEqual([{ key: "model", file: alternate }]);
});

test("unreadable native file preserves its baseline and does not spoil a published snapshot", async () => {
  await apply(files); put(files.native.claude, '{broken'); prefs("claude", "new");
  expect((await apply(files)).harnesses.claude.error).toContain("native settings");
  expect(JSON.parse(readFileSync(resolvePreferences("claude", files), "utf8")).model).toBe("new");
  put(files.native.claude, '{"model":"ui-change"}');
  expect((await apply(files)).harnesses.claude.drift).toHaveLength(1);
});

test("captured temporary profile edits survive deletion, keep values private, and allow explicit resolution", async () => {
  await apply(files);
  captureEdits("codex", {model:"gpt-test", projects:{}}, {model:"keep-this-private", projects:{a:1}}, {model:"gpt-test"}, files);
  const event = join(files.root, "events", readdirSync(join(files.root, "events"))[0]);
  expect(readFileSync(event, "utf8")).toContain("keep-this-private");
  expect(statSync(event).mode & 0o777).toBe(0o600);
  const report = await apply(files);
  expect(report.harnesses.codex.drift).toEqual([{key:"model", file:event}]);
  expect(JSON.stringify(report)).not.toContain("keep-this-private");
  expect((await apply(files)).notices).toEqual([]);
  prefs("codex", "keep-this-private");
  expect((await apply(files)).harnesses.codex.drift).toEqual([]);
  expect(existsSync(event)).toBe(true);
});

test("malformed events stay pending; corrupted snapshots recover only from valid source", async () => {
  await apply(files); const snapshot = resolvePreferences("codex", files);
  put(snapshot, 'bad=['); await apply(files);
  expect(readFileSync(snapshot, "utf8")).toContain("gpt-test");
  put(snapshot, 'model="tampered"'); put(files.sources.codex, 'bad=[');
  expect(() => resolvePreferences("codex", files)).toThrow("modified");
  prefs("codex", "valid");
  put(join(files.root, "events", "123-abcd.json"), '{"version":1,"harness":"codex","changes":null}');
  expect((await apply(files)).harnesses.codex.error).toContain("invalid watcher event");
  expect(JSON.parse(readFileSync(join(files.root,"state.json"),"utf8")).handledEvents).toEqual([]);
});

test("concurrent publishers serialize and the kernel releases a killed daemon lock", async () => {
  const publishers = Array.from({length:6}, () => launch(["config","apply","--json"]));
  expect(await Promise.all(publishers.map(c => c.exited))).toEqual([0,0,0,0,0,0]);
  const watcher = launch(["config","watch"]);
  await until(() => status(files).watcherRunning);
  const duplicate = launch(["config","watch"]);
  expect(await duplicate.exited).toBe(1);
  watcher.kill("SIGKILL"); await watcher.exited;
  expect(status(files).watcherRunning).toBe(false);
  const replacement = launch(["config","watch"]);
  await until(() => status(files).watcherRunning);
  replacement.kill("SIGTERM"); expect(await replacement.exited).toBe(0);
  expect(status(files).watcherRunning).toBe(false);
});

test("real filesystem watcher follows atomic saves and newly registered homes, without spinning", async () => {
  const abort = new AbortController(); const running = watchConfigs(files, false, abort.signal);
  try {
    await until(() => status(files).harnesses.codex.status === "ready-for-next-launch");
    const initial = status(files).checkedAt;
    await Bun.sleep(1100); expect(status(files).checkedAt).toBe(initial);
    put(files.sources.codex + ".tmp", 'model="atomic"'); renameSync(files.sources.codex + ".tmp", files.sources.codex);
    await until(() => status(files).checkedAt !== initial);
    expect(readFileSync(resolvePreferences("codex", files),"utf8")).toContain("atomic");
    const alt = join(root,"new/home/config.toml"); put(alt,'model="base"'); registerNativeHome("codex",alt,files);
    await until(() => (status(files).harnesses.codex.shadowed || []).some((s:any) => s.file === alt));
    put(alt,'model="edited"');
    await until(() => status(files).harnesses.codex.drift?.some((d:any) => d.file === alt));
  } finally { abort.abort(); await running; }
  expect(status(files).watcherRunning).toBe(false);
}, 15000);

test("notifications are grouped, deduplicated by reconciliation, and contain no preference values", async () => {
  const bin = join(root,"bin"); mkdirSync(bin);
  const receipt = join(root,"notifications");
  put(join(bin,"funk-notify"), '#!/usr/bin/env python3\nimport sys,json\nwith open('+JSON.stringify(receipt)+',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n');
  const { chmodSync } = await import("node:fs"); chmodSync(join(bin,"funk-notify"),0o755);
  const old = process.env.PATH; process.env.PATH = bin + ":" + old;
  try {
    await notify((await apply(files)).notices); expect(existsSync(receipt)).toBe(false);
    put(files.native.codex,'model="secret-value"');
    await notify((await apply(files)).notices); await notify((await apply(files)).notices);
    const text = readFileSync(receipt,"utf8"); expect(text.trim().split("\n")).toHaveLength(1);
    expect(text).toContain("io.arthack.agentstart.config.codex"); expect(text).not.toContain("secret-value");
  } finally { process.env.PATH = old; }
});

test("managed wrappers consume last good snapshots and Codex records native profile edits before cleanup", async () => {
  await apply(files); put(files.sources.codex,'broken=['); put(files.claudeStowSource,'{broken');
  const probe = join(root,"probe");
  put(probe, `#!/usr/bin/env python3
import os,sys,pathlib,json
if sys.argv[1]=='--profile':
 p=pathlib.Path(os.environ['CODEX_HOME'])/(sys.argv[2]+'.config.toml')
 assert 'gpt-test' in p.read_text()
 p.write_text('model="ui-edited"\\n')
else:
 assert sys.argv[1]=='--settings'
 assert json.loads(pathlib.Path(sys.argv[2]).read_text())['model']=='sonnet'
`);
  const {chmodSync} = await import("node:fs"); chmodSync(probe,0o755);
  for (const harness of ["claude","codex"]) {
    const child = Bun.spawn([resolve(import.meta.dir, `../scripts/${harness}-invocation`),probe,"hello"], {
      env:{...environment(),AGENTSTART_CLAUDE_TRUST:"0"},cwd:root,stdout:"pipe",stderr:"pipe",
    }); children.push(child);
    expect(await child.exited).toBe(0);
  }
  expect(readdirSync(join(root,".codex")).filter(n=>n.startsWith("agentstart-invocation"))).toEqual([]);
  prefs("codex","gpt-test");
  expect((await apply(files)).harnesses.codex.drift).toHaveLength(1);
  expect(readFileSync(files.sources.codex,"utf8")).not.toContain("ui-edited");
});

test("periodic reconciliation catches a missed event and replacement of the source directory", async () => {
  const newSource = join(root,"elsewhere/preferences.toml"); put(newSource,'model="fallback"');
  const abort = new AbortController();
  const running = watchConfigs(files, false, abort.signal, {debounceMs:20,reconcileMs:250});
  try {
    await until(() => !!status(files).checkedAt);
    await Bun.sleep(100);
    // Move to an existing unwatched location, so no watched pathname event
    // advertises the edit. The interval must discover the new source.
    files.sources.codex = newSource;
    await until(() => status(files).harnesses.codex.source === newSource);
    expect(readFileSync(resolvePreferences("codex",files),"utf8")).toContain("fallback");
    renameSync(dirname(newSource),dirname(newSource)+"-old"); put(newSource,'model="directory-replaced"');
    await until(() => readFileSync(status(files).harnesses.codex.snapshot,"utf8").includes("directory-replaced"));
    put(newSource,'model="after-replace"');
    await until(() => readFileSync(status(files).harnesses.codex.snapshot,"utf8").includes("after-replace"));
  } finally { abort.abort(); await running; }
});

test("CLI installation is rerunnable, embeds its checkout, and refuses independent commands", async () => {
  const bin = join(root,"bin"); mkdirSync(bin);
  for (const [name, body] of Object.entries({uname:"printf Darwin",id:"printf 501",agentlaunch:"exit 0"})) {
    put(join(bin,name),"#!/bin/sh\n"+body+"\n");
    const {chmodSync} = await import("node:fs"); chmodSync(join(bin,name),0o755);
  }
  const installer = resolve(import.meta.dir,"../scripts/install-agentlaunch-shims");
  const run = () => {
    const child = Bun.spawn([installer],{env:{...environment(),PATH:bin+":"+process.env.PATH,AGENTSTART_INSTALL_BIN_DIR:join(root,"installed")},stdout:"pipe",stderr:"pipe"});
    children.push(child); return child.exited;
  };
  expect(await run()).toBe(0); expect(await run()).toBe(0);
  const installed = join(root,"installed/agentstart");
  expect(readFileSync(installed,"utf8")).toContain(cli);
  put(installed,"#!/bin/sh\n# independent\n");
  expect(await run()).toBe(1); expect(readFileSync(installed,"utf8")).toContain("independent");
});

test("a later captured return to the authored value resolves earlier profile drift", async () => {
  await apply(files);
  captureEdits("codex",{model:"gpt-test"},{model:"edited"},{model:"gpt-test"},files);
  expect((await apply(files)).harnesses.codex.drift).toHaveLength(1);
  await Bun.sleep(2);
  captureEdits("codex",{model:"edited"},{model:"gpt-test"},{model:"gpt-test"},files);
  expect((await apply(files)).harnesses.codex.drift).toEqual([]);
});

test("invalid native profile edits are retained and notified without hiding the native exit status", async () => {
  await apply(files);
  const bin=join(root,"bin"), receipt=join(root,"notice"); mkdirSync(bin);
  const {chmodSync} = await import("node:fs");
  put(join(bin,"funk-notify"),'#!/usr/bin/env python3\nimport pathlib\npathlib.Path('+JSON.stringify(receipt)+').write_text("notified")\n'); chmodSync(join(bin,"funk-notify"),0o755);
  const probe=join(bin,"probe");
  put(probe,'#!/usr/bin/env python3\nimport os,pathlib,sys\np=pathlib.Path(os.environ["CODEX_HOME"])/(sys.argv[2]+".config.toml")\np.write_text("invalid=[")\nsys.exit(42)\n'); chmodSync(probe,0o755);
  const child=Bun.spawn([resolve(import.meta.dir,"../scripts/codex-invocation"),probe,"hello"],{
    cwd:root,env:{...environment(),PATH:bin+":"+process.env.PATH},stdout:"pipe",stderr:"pipe",
  });children.push(child);
  expect(await child.exited).toBe(42);
  expect(await new Response(child.stderr).text()).toContain("retained");
  const profiles=readdirSync(join(root,".codex")).filter(n=>n.startsWith("agentstart-invocation"));
  expect(profiles).toHaveLength(1); expect(readFileSync(join(root,".codex",profiles[0]),"utf8")).toBe("invalid=[");
  expect(readFileSync(receipt,"utf8")).toBe("notified");
});

test("account-launcher temporary home cleanup is quiet while native file deletion remains visible", async () => {
  const temporary = join(root,"runtime-shadow-homes/account/config.toml");
  put(temporary,'model="ambient"'); registerNativeHome("codex",temporary,files);
  await apply(files);
  rmSync(dirname(temporary),{recursive:true});
  const report = await apply(files);
  expect(report.notices).toEqual([]); expect(report.harnesses.codex.drift).toEqual([]);
  expect(report.harnesses.codex.shadowed.some((s:any) => s.file === temporary)).toBe(false);
  // A file can disappear before its parent is removed. That temporary
  // missing-file report must resolve when the home lifecycle completes.
  put(temporary,'model="ambient"'); await apply(files);
  unlinkSync(temporary); expect((await apply(files)).harnesses.codex.drift).toHaveLength(1);
  rmSync(dirname(temporary),{recursive:true});
  expect((await apply(files)).harnesses.codex.drift).toEqual([]);
  unlinkSync(files.native.codex);
  expect((await apply(files)).harnesses.codex.drift).toEqual([{key:"model",file:files.native.codex}]);
});
