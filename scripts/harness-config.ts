import { createHash, randomUUID } from "node:crypto";
import { existsSync, closeSync, lstatSync, openSync, mkdirSync, readFileSync, readdirSync, realpathSync, renameSync, unlinkSync, watch, writeFileSync } from "node:fs";
import { dlopen, FFIType } from "bun:ffi";
import { homedir } from "node:os";
import { basename, dirname, join, relative, resolve, sep } from "node:path";

export type Harness = "claude" | "codex";
type ObjectValue = Record<string, any>;
export type Layout = ReturnType<typeof layout>;
const harnesses: Harness[] = ["claude", "codex"];
const object = (value: any): value is ObjectValue => value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof Date);
const digest = (value: string) => createHash("sha256").update(value).digest("hex");
const canonical = (value: any): any => Array.isArray(value) ? value.map(canonical) : object(value) ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const stable = (value: any): string => JSON.stringify(canonical(value));
const hash = (value: any) => digest(value === undefined ? "absent" : "value:" + stable(value));
const absent = undefined;
const valueAt = (value: any, path: string[]): any => path.reduce((v, key) => object(v) && Object.hasOwn(v, key) ? v[key] : absent, value);
const keyOf = (path: string[]) => JSON.stringify(path);

export function layout(home = homedir(), stateBase = process.env.XDG_STATE_HOME || join(home, ".local/state")) {
  return {
    home, root: join(stateBase, "agentstart/harness-config"),
    sources: { claude: join(home, ".claude/preferences.json"), codex: join(home, "code/funk/config/harnesses/codex.toml") },
    claudeStowSource: join(home, "code/funk/claude/.claude/preferences.json"),
    native: { claude: join(home, ".claude/settings.json"), codex: join(home, ".codex/config.toml") },
  };
}

function pathsOf(value: ObjectValue, prefix: string[] = []): string[][] {
  return Object.entries(value).flatMap(([key, val]) => object(val) && Object.keys(val).length ? pathsOf(val, [...prefix, key]) : [[...prefix, key]]);
}
function fingerprints(value: ObjectValue, paths: string[][]): ObjectValue {
  return Object.fromEntries(paths.map(path => [keyOf(path), hash(valueAt(value, path))]));
}
function atomic(path: string, bytes: string) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const temp = join(dirname(path), `.${basename(path)}.${randomUUID()}`);
  try { writeFileSync(temp, bytes, { flag: "wx", mode: 0o600 }); renameSync(temp, path); }
  finally { if (existsSync(temp)) unlinkSync(temp); }
}
function readJSON(path: string) { return JSON.parse(readFileSync(path, "utf8")); }

export function parse(harness: Harness, bytes: string): ObjectValue {
  let data;
  try { data = harness === "claude" ? JSON.parse(bytes) : Bun.TOML.parse(bytes); }
  catch { throw new Error(`${harness}: invalid ${harness === "claude" ? "JSON" : "TOML"}`); }
  if (!object(data)) throw new Error(`${harness}: preferences must be an object`);
  return data;
}
export function validate(harness: Harness, data: ObjectValue) {
  const reserved = harness === "claude" ? ["projects", "oauthAccount", "primaryApiKey", "autoMode", "hooks", "statusLine"] : ["projects", "profile", "profiles"];
  for (const key of reserved) if (Object.hasOwn(data, key)) throw new Error(`${harness}: ${key} belongs in native state, not tracked preferences`);
  for (const key of ["model", "model_reasoning_effort", "service_tier", "effortLevel"]) {
    if (key in data && typeof data[key] !== "string") throw new Error(`${harness}: ${key} must be a string`);
  }
  for (const key of ["permissions", "features", "agents", "env", "modelSettings", "enabledPlugins"]) {
    if (key in data && !object(data[key])) throw new Error(`${harness}: ${key} must be an object`);
  }
}
function source(layout: Layout, harness: Harness) {
  const file = layout.sources[harness];
  if (harness === "claude" && existsSync(layout.claudeStowSource)) {
    if (!lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink() || realpathSync(file) !== realpathSync(layout.claudeStowSource)) {
      throw new Error("claude: preferences link differs from Funk; review with funk stow --check claude");
    }
  }
  if (!lstatSync(file, { throwIfNoEntry: false })) return null;
  const bytes = readFileSync(file, "utf8");
  const settings = parse(harness, bytes); validate(harness, settings);
  return { bytes, settings, signature: hash(settings), paths: pathsOf(settings) };
}
function readState(layout: Layout): ObjectValue {
  const file = join(layout.root, "state.json");
  if (!existsSync(file)) return { version: 1, harnesses: {}, handledEvents: [] };
  const value = readJSON(file);
  if (value.version !== 1 || !object(value.harnesses) || !Array.isArray(value.handledEvents)) throw new Error("configuration watcher state is invalid; preserve it for inspection");
  return value;
}
function snapshotPath(layout: Layout, harness: Harness, signature: string) {
  if (!/^[a-f0-9]{64}$/.test(signature)) throw new Error("invalid snapshot signature");
  return join(layout.root, "snapshots", `${harness}-${signature}.${harness === "claude" ? "json" : "toml"}`);
}
function snapshot(layout: Layout, harness: Harness, info: any) {
  const path = snapshotPath(layout, harness, info.signature);
  let valid = false;
  try { valid = hash(parse(harness, readFileSync(path, "utf8"))) === info.signature; } catch {}
  if (!valid) atomic(path, info.bytes);
  return path;
}

/** Consumers preserve normal source reads until the watcher publishes a
 * snapshot. An invalid edit can use the last proved snapshot; custom sources
 * continue to use their original strict invocation contract. */
export function resolvePreferences(harness: Harness, files = layout()): string {
  let info: ReturnType<typeof source>, error: unknown;
  try { info = source(files, harness); }
  catch (caught) { error = caught; }
  const state = readState(files).harnesses[harness];
  if (info) {
    if (state?.signature === info.signature && state?.source === files.sources[harness]) {
      const file = snapshotPath(files, harness, state.signature);
      try { if (hash(parse(harness, readFileSync(file, "utf8"))) === state.signature) return file; } catch {}
    }
    return files.sources[harness];
  }
  if (state?.signature && state.source === files.sources[harness]) {
    const file = snapshotPath(files, harness, state.signature);
    const data = parse(harness, readFileSync(file, "utf8")); validate(harness, data);
    if (hash(data) !== state.signature) throw new Error(`${harness}: last good snapshot was modified`);
    console.error(`${harness}: preferences unavailable or invalid; using last good snapshot. Run agentstart config status.`);
    return file;
  }
  if (error) throw error;
  return files.sources[harness];
}

export function registerNativeHome(harness: Harness, nativeFile: string, files = layout()) {
  const path = resolve(nativeFile);
  const record = join(files.root, "homes", `${digest(harness + path)}.json`);
  if (!existsSync(record)) atomic(record, JSON.stringify({ harness, path }) + "\n");
}
function nativeFiles(files: Layout, harness: Harness) {
  const result = new Set([files.native[harness]]), directory = join(files.root, "homes");
  if (existsSync(directory)) for (const name of readdirSync(directory)) {
    if (!/^[a-f0-9]{64}\.json$/.test(name)) continue;
    const record = readJSON(join(directory, name));
    if (record.harness === harness && typeof record.path === "string" && resolve(record.path) === record.path) result.add(record.path);
  }
  return [...result];
}

/** Capture only changed authored fields before a temporary Codex profile is
 * deleted. The private event retains values for manual review, never writes
 * them to Funk, and never prints them in status or notification text. */
export function captureEdits(harness: Harness, before: ObjectValue, after: ObjectValue, authored: ObjectValue, files = layout(), nativeFile?: string) {
  const changes = pathsOf(authored).filter(path => hash(valueAt(before, path)) !== hash(valueAt(after, path)))
    .map(path => ({ path, value: valueAt(after, path), missing: valueAt(after, path) === absent, expected: hash(valueAt(authored, path)) }));
  if (!changes.length) return;
  const event = { version: 1, harness, at: new Date().toISOString(), nativeFile, changes };
  atomic(join(files.root, "events", `${Date.now()}-${randomUUID()}.json`), JSON.stringify(event) + "\n");
}

// Kernel-owned advisory locks release even on SIGKILL. Never unlink the lock
// inode: replacing it would let two processes lock different files at one path.
const libc = dlopen(process.platform === "darwin" ? "/usr/lib/libSystem.B.dylib" : "libc.so.6", {
  flock: { args: [FFIType.i32, FFIType.i32], returns: FFIType.i32 },
});
function lock(files: Layout, name: string) {
  mkdirSync(files.root, { recursive: true, mode: 0o700 });
  return openSync(join(files.root, name), "a", 0o600);
}
async function exclusive<T>(files: Layout, fn: () => T | Promise<T>, name = "apply.lock"): Promise<T> {
  const fd = lock(files, name);
  try {
    for (let attempt = 0; libc.symbols.flock(fd, 2 | 4) !== 0; attempt++) {
      if (attempt >= 30) throw new Error("configuration watcher is busy; retry shortly");
      await Bun.sleep(50);
    }
    return await fn();
  } finally { closeSync(fd); }
}

function publicStatus(state: ObjectValue) {
  return {
    checkedAt: state.checkedAt,
    harnesses: Object.fromEntries(harnesses.map(harness => {
      const entry = state.harnesses[harness];
      return [harness, entry ? { source: entry.source, status: entry.error ? "invalid" : entry.signature ? "ready-for-next-launch" : "not-configured",
        error: entry.error || null, snapshot: entry.snapshot || null, appliedAt: entry.appliedAt,
        drift: Object.values(entry.drift || {}).map((item: any) => ({ key: item.path.join("."), file: item.file })),
        shadowed: entry.shadowed || [] } : { status: "not-checked" }];
    })),
  };
}
export function status(files = layout()) {
  let running = false;
  // A read-only status does not create state on an unconfigured machine.
  if (existsSync(join(files.root, "watch.lock"))) {
    const fd = openSync(join(files.root, "watch.lock"), "r");
    try { running = libc.symbols.flock(fd, 2 | 4) !== 0; } finally { closeSync(fd); }
  }
  return { watcherRunning: running, ...publicStatus(readState(files)) };
}

export async function apply(files = layout(), acknowledge = false) {
  return exclusive(files, () => {
    const state = readState(files), notices: { harness: Harness; kind: string; message: string }[] = [];
    const eventsDir = join(files.root, "events");
    const events = existsSync(eventsDir) ? readdirSync(eventsDir).filter(name => /^[0-9]+-[a-f0-9-]+\.json$/.test(name)).sort() : [];
    const pending = events.filter(name => !state.handledEvents.includes(name));
    const handled: string[] = [];
    for (const harness of harnesses) {
      const previous = state.harnesses[harness] || {}, entry = { ...previous, source: files.sources[harness], drift: { ...previous.drift } };
      const previousIssue = stable({ error: previous.error || null, drift: previous.drift || {} });
      let info;
      try {
        info = source(files, harness);
        if (!info) {
          if (previous.signature) throw new Error(`${harness}: authored preferences are missing; retaining last good snapshot`);
          entry.error = null;
        } else {
          entry.snapshot = snapshot(files, harness, info);
          entry.signature = info.signature; entry.error = null;
          if (previous.signature !== info.signature) entry.appliedAt = new Date().toISOString();
          const wanted = fingerprints(info.settings, info.paths);
          entry.native = { ...previous.native }; entry.shadowed = [];
          const nativeErrors: string[] = [];
          for (const nativeFile of nativeFiles(files, harness)) {
            try {
              const native = existsSync(nativeFile) ? parse(harness, readFileSync(nativeFile, "utf8")) : {};
              const observed = fingerprints(native, info.paths);
              for (const path of info.paths) {
                const key = keyOf(path), driftKey = nativeFile + "\0" + key;
                if (observed[key] === wanted[key]) delete entry.drift[driftKey];
                else if (previous.native?.[nativeFile]?.[key] && previous.native[nativeFile][key] !== observed[key]) entry.drift[driftKey] = { path, file: nativeFile, valueHash: observed[key] };
              }
              entry.shadowed.push(...info.paths.filter(path => valueAt(native, path) !== absent && observed[keyOf(path)] !== wanted[keyOf(path)]).map(path => ({ key: path.join("."), file: nativeFile })));
              entry.native[nativeFile] = observed;
            } catch { nativeErrors.push(nativeFile); }
          }
          if (nativeErrors.length) entry.error = `${harness}: cannot read native settings: ${nativeErrors.join(", ")}`;
          for (const name of pending) {
            const event = readJSON(join(eventsDir, name));
            if (event.version !== 1 || !harnesses.includes(event.harness) || !Array.isArray(event.changes)
                || event.changes.some((c: any) => !object(c) || !Array.isArray(c.path) || !c.path.length || !c.path.every((p: any) => typeof p === "string"))) {
              throw new Error("invalid watcher event; preserve events for inspection");
            }
            if (event.harness !== harness) continue;
            handled.push(name);
            for (const change of event.changes) {
              if (!Array.isArray(change.path) || !change.path.every((part: any) => typeof part === "string")) continue;
              const key = keyOf(change.path);
              if (wanted[key] && hash(change.missing ? absent : change.value) !== wanted[key]) entry.drift["event\0" + key] = { path: change.path, file: join(eventsDir, name), valueHash: hash(change.missing ? absent : change.value) };
              else delete entry.drift["event\0" + key];
            }
          }
          for (const [key, drift] of Object.entries(entry.drift) as [string, any][]) {
            const field = keyOf(drift.path);
            if (!wanted[field] || drift.valueHash === wanted[field]) delete entry.drift[key];
          }
          if (acknowledge) entry.drift = {};
        }
      } catch (error: any) {
        // Never include parse input, raw values, or exception stacks in state
        // and desktop notifications. Our validation errors contain keys only.
        entry.error = error.code ? `${harness}: cannot read or publish preferences (${error.code})` : error instanceof SyntaxError ? `${harness}: invalid watcher event JSON` : error.message;
      }
      const issue = stable({ error: entry.error || null, drift: entry.drift || {} });
      if (issue !== previousIssue && (entry.error || Object.keys(entry.drift).length)) notices.push({ harness, kind: "attention", message: entry.error || `${harness}: local preference edits need review (${Object.values(entry.drift).map((d: any) => d.path.join(".")).join(", ")}). Run agentstart config status.` });
      else if ((previous.error || Object.keys(previous.drift || {}).length) && !entry.error && !Object.keys(entry.drift).length) notices.push({ harness, kind: "recovered", message: `${harness}: preferences are ready; previous issues resolved.` });
      else if (!entry.error && !Object.keys(entry.drift).length && previous.signature && info && previous.signature !== info.signature) notices.push({ harness, kind: "applied", message: `${harness}: preference changes applied for the next launch.` });
      state.harnesses[harness] = entry;
    }
    state.handledEvents = [...new Set([...state.handledEvents, ...handled])];
    state.checkedAt = new Date().toISOString();
    atomic(join(files.root, "state.json"), JSON.stringify(state, null, 2) + "\n");
    return { ...publicStatus(state), notices };
  });
}

export async function notify(notices: { harness: Harness | "watcher"; kind: string; message: string }[]) {
  const binary = Bun.which("funk-notify", { PATH: process.env.PATH });
  if (!binary) { if (notices.length) console.error("agentstart config: funk-notify is unavailable; review agentstart config status"); return; }
  for (const item of notices) {
    try {
      const child = Bun.spawn([binary, "--title", "Harness preferences", "--message", item.message.slice(0, 400), "--group", `io.arthack.agentstart.config.${item.harness}`], { stdout: "ignore", stderr: "ignore" });
      const deadline = setTimeout(() => child.kill("SIGKILL"), 5000);
      try { if (await child.exited !== 0) console.error("agentstart config: notification delivery failed; review agentstart config status"); }
      finally { clearTimeout(deadline); }
    } catch { console.error("agentstart config: notification delivery failed; review agentstart config status"); }
  }
}

export async function watchConfigs(files = layout(), sendNotifications = false, signal?: AbortSignal, timing = { debounceMs: 750, reconcileMs: 30_000 }) {
  return exclusive(files, () => watchLoop(files, sendNotifications, signal, timing), "watch.lock");
}
async function watchLoop(files: Layout, sendNotifications: boolean, signal: AbortSignal | undefined, timing: { debounceMs: number; reconcileMs: number }) {
  let closed = false, running = false, again = false, lastError = "";
  const watchers = new Map<string, ReturnType<typeof watch>>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  function directories() {
    const targets = [...Object.values(files.sources), ...harnesses.flatMap(harness => nativeFiles(files, harness)), files.claudeStowSource, join(files.root, "events", "*"), join(files.root, "homes", "*")];
    const result = new Map<string, Set<string>>();
    for (const file of targets) {
      let dir = dirname(file);
      while (!existsSync(dir) && dirname(dir) !== dir) dir = dirname(dir);
      const names = result.get(dir) || new Set<string>();
      names.add(relative(dir, file).split(sep)[0]); result.set(dir, names);
    }
    return result;
  }
  function arm() {
    if (closed) return;
    // Reopen after reconciliation: editors can replace an entire directory,
    // leaving a pathname-identical watcher attached to the old inode.
    const targets = directories();
    for (const handle of watchers.values()) handle.close();
    watchers.clear();
    for (const [dir, names] of targets) {
      try {
        const handle = watch(dir, (_event, filename) => {
          // Match against the registration-time parent. A newly created child
          // directory changes directories(), but its parent event still matters.
          if (!filename || names.has(filename.toString()) || names.has("*")) schedule();
        });
        handle.on("error", () => { handle.close(); watchers.delete(dir); schedule(); });
        watchers.set(dir, handle);
      } catch {}
    }
  }

  async function check() {
    if (closed) return;
    if (running) { again = true; return; }
    running = true;
    try {
      const report = await apply(files);
      arm();
      if (sendNotifications) {
        await notify(report.notices);
        if (lastError) await notify([{ harness: "watcher", kind: "recovered", message: "Configuration watcher recovered. Run agentstart config status." }]);
      }
      lastError = "";
    } catch (error: any) {
      const message = error instanceof SyntaxError ? "Invalid watcher state or home registry JSON" : error.message;
      console.error(`agentstart config watch: ${message}`);
      if (message !== lastError && sendNotifications) await notify([{ harness: "watcher", kind: "attention", message: "Configuration watcher failed. Inspect config-watch.log and run agentstart config status." }]);
      lastError = message;
    } finally { running = false; if (again) { again = false; schedule(); } }
  }
  function schedule() { if (!closed) { clearTimeout(timer); timer = setTimeout(check, timing.debounceMs); } }
  await check();
  // Filesystem events are hints. Periodic reconciliation catches missed events,
  // sleep/wake, directory replacement, and the first appearance of a source.
  const interval = setInterval(check, timing.reconcileMs);
  await new Promise<void>(done => {
    const stop = () => { closed = true; clearTimeout(timer); clearInterval(interval); for (const handle of watchers.values()) handle.close(); done(); };
    if (signal?.aborted) stop(); else signal?.addEventListener("abort", stop, { once: true });
  });
  while (running) await Bun.sleep(10);
}
