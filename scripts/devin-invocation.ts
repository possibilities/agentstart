#!/usr/bin/env bun
/** Terminal Devin sessions run in place with a disposable, Role-equipped .devin. */
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { lstatSync, mkdirSync, openSync, closeSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync, renameSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { homedir } from "node:os";
import { processIdentity, type ProcessIdentity } from "./devin-process.ts";

const utilities = new Set(["acp", "auth", "mcp", "models", "skills", "rules", "plugins", "version", "doctor", "update", "setup", "cloud", "ssh", "forward", "worker", "uninstall", "help", "sandbox", "airgap"]);
const resumeFlags = new Set(["-c", "--continue", "-r", "--resume"]);
const skillName = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const mcpName = /^[a-z][a-z0-9_-]*$/;
const uuidShape = /^[0-9a-f-]{36}$/;
const markerRel = "agentstart-owner.json";
export const owner = "agentstart-devin-invocation-v1";

export type Invocation = {
  owner: typeof owner;
  id: string;
  snapshot: string;
  created: boolean;
  cwd: string;
  wrapper: ProcessIdentity;
  child?: ProcessIdentity;
  files?: Record<string, string>;
};
export function invocationDir(env: NodeJS.ProcessEnv = process.env): string {
  const home = env.HOME ?? homedir();
  // A fixed home-relative path lets the LaunchAgent see every terminal invocation,
  // even when a caller overrides XDG_STATE_HOME for an unrelated tool.
  return join(home, ".local", "state", "agentstart", "devin-invocations");
}
export function invocationPath(dir: string, cwd: string, id: string): string {
  return join(dir, `${createHash("sha256").update(cwd).digest("hex")}-${id}.json`);
}
export function invocationRecords(dir: string, cwd: string): string[] {
  const prefix = createHash("sha256").update(cwd).digest("hex");
  try {
    return readdirSync(dir)
      .filter(name => name === `${prefix}.json` || (name.startsWith(`${prefix}-`) && name.endsWith(".json")))
      .map(name => join(dir, name));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
}

function safeRole(root: string): string {
  const role = join(root, "roles", "default");
  for (const file of ["APPEND_SYSTEM_PROMPT.md", "mcp.json"]) if (!statSync(join(role, file)).isFile()) throw new Error(`default Role is incomplete: ${file}`);
  if (!statSync(join(role, "skills")).isDirectory()) throw new Error("default Role has no skills directory");
  return role;
}

function expandHome(value: string, home: string): string { return value.replaceAll("${HOME}", home); }
function renderMcp(role: string, home: string): string {
  const value = JSON.parse(readFileSync(join(role, "mcp.json"), "utf8")) as { mcpServers?: Record<string, unknown> };
  if (!value.mcpServers || typeof value.mcpServers !== "object" || Array.isArray(value.mcpServers)) throw new Error("default Role MCP definition is invalid");
  const servers: Record<string, unknown> = {};
  for (const [name, entry] of Object.entries(value.mcpServers)) {
    if (!mcpName.test(name) || !entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error("invalid Role MCP server");
    const server = entry as { command?: unknown; args?: unknown[]; env?: Record<string, unknown>; url?: unknown; headers?: Record<string, unknown> };
    if (typeof server.command === "string" && Array.isArray(server.args) && server.args.every((arg) => typeof arg === "string")) {
      servers[name] = { command: expandHome(server.command, home), args: server.args.map((arg) => expandHome(arg as string, home)),
        ...(server.env ? { env: Object.fromEntries(Object.entries(server.env).map(([key, val]) => {
          if (typeof val !== "string") throw new Error("Role MCP environment must be strings");
          return [key, expandHome(val, home)];
        })) } : {}) };
    } else if (typeof server.url === "string") {
      const url = new URL(expandHome(server.url, home));
      if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error("Role MCP URL is invalid");
      servers[name] = { url: url.toString(), transport: "http", ...(server.headers ? { headers: server.headers } : {}) };
    } else throw new Error(`Role MCP ${name} has no supported transport`);
  }
  return JSON.stringify({ mcpServers: servers }, null, 2) + "\n";
}

/** Every file the snapshot renders inside .devin, except the marker and .gitignore. */
function expectedEntries(role: string, home: string): Map<string, Buffer> {
  const entries = new Map<string, Buffer>();
  entries.set("config.json", Buffer.from(JSON.stringify({ read_config_from: {
    agents_standard: true, cursor: false, windsurf: false, claude: false, copilot: false, opencode: false, zed: false,
  } }, null, 2) + "\n"));
  entries.set("mcp_config.local.json", Buffer.from(renderMcp(role, home)));
  const sourceSkills = join(role, "skills");
  const visit = (dir: string, prefix: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      const path = join(dir, entry.name);
      if (entry.isDirectory()) visit(path, relative);
      else entries.set(relative, readFileSync(path));
    }
  };
  for (const name of readdirSync(sourceSkills)) {
    if (!skillName.test(name) || name === "prime") throw new Error(`unsupported or reserved Role skill name: ${name}`);
    const source = join(sourceSkills, name);
    if (!statSync(source).isDirectory() || !statSync(join(source, "SKILL.md")).isFile()) throw new Error(`invalid Role skill: ${name}`);
    visit(source, `skills/${name}`);
  }
  const instructions = readFileSync(join(role, "APPEND_SYSTEM_PROMPT.md"), "utf8");
  entries.set("skills/prime/SKILL.md", Buffer.from(`---\nname: prime\ndescription: Load AgentStart's working instructions when explicitly invoked\ntriggers: [user]\n---\n\n${instructions}\n`));
  return entries;
}

/** Creates missing directories below target; foreign symlinks and files refuse. */
function ensureDirectory(target: string, relative: string, ownedDirs: Set<string>): boolean {
  let directory = target;
  for (const part of relative.split("/")) {
    directory = join(directory, part);
    const prefix = directory.slice(target.length + 1);
    try {
      const stat = lstatSync(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink()) return false;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      mkdirSync(directory, { mode: 0o700 });
      ownedDirs.add(prefix);
    }
  }
  return true;
}

function hashOf(content: Buffer | string): string {
  return createHash("sha256").update(content).digest("hex");
}

type Claim = "claimed" | "missing" | "conflict";
/** Claims an existing identical file, or writes it when allowed. Never overwrites. */
function claimFile(target: string, relative: string, content: Buffer, write: boolean, ownedDirs: Set<string>): Claim {
  const path = join(target, relative);
  const expected = hashOf(content);
  try {
    const stat = lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()) return "conflict";
    return hashOf(readFileSync(path)) === expected ? "claimed" : "conflict";
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  if (!write) return "missing";
  const parent = relative.includes("/") ? relative.slice(0, relative.lastIndexOf("/")) : "";
  if (parent && !ensureDirectory(target, parent, ownedDirs)) return "conflict";
  try {
    writeFileSync(path, content, { mode: 0o600, flag: "wx" });
    return "claimed";
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    // A concurrent invocation wrote the same path; adopt it if identical.
    try {
      const stat = lstatSync(path);
      if (!stat.isFile() || stat.isSymbolicLink()) return "conflict";
      return hashOf(readFileSync(path)) === expected ? "claimed" : "conflict";
    } catch (inner) {
      if ((inner as NodeJS.ErrnoException).code === "ENOENT") return "conflict";
      throw inner;
    }
  }
}

function canonicalMarker(id: string): string { return JSON.stringify({ owner, id }); }

/** Returns the snapshot id a present marker adopts, or throws for foreign markers. */
function adoptMarker(target: string): { id: string; text: string } | null {
  const marker = join(target, markerRel);
  let stat;
  try { stat = lstatSync(marker); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error("project .devin ownership marker is not a regular file");
  const text = readFileSync(marker, "utf8");
  let claim: { owner?: string; id?: string };
  try { claim = JSON.parse(text); } catch { throw new Error("project .devin ownership marker is unreadable"); }
  if (claim.owner !== owner || typeof claim.id !== "string" || !uuidShape.test(claim.id) || text !== canonicalMarker(claim.id)) {
    throw new Error("project .devin carries a foreign ownership marker; refusing to claim it");
  }
  return { id: claim.id, text };
}

function renderGitignore(claimed: Iterable<string>, ownedDirs: Set<string>): string {
  const lines = new Set<string>();
  for (const relative of claimed) {
    const parts = relative.split("/");
    if (parts.length === 1) { lines.add(`/${relative}`); continue; }
    let prefix = "", entry = `/${relative}`;
    for (let i = 0; i < parts.length - 1; i++) {
      prefix = prefix ? `${prefix}/${parts[i]}` : parts[i];
      if (ownedDirs.has(prefix)) { entry = `/${prefix}/`; break; }
    }
    lines.add(entry);
  }
  return `# AgentStart Devin invocation snapshot.\n/.gitignore\n${[...lines].sort().join("\n")}\n`;
}

export function prepareDevinInvocation(cwd: string, home: string, resourcesRoot: string, stateDir: string): { repo: string; record: string; invocation: Invocation; conflicts: string[] } {
  const repo = realpathSync(execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim());
  const role = safeRole(resourcesRoot);
  mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  if (lstatSync(stateDir).isSymbolicLink()) throw new Error("Devin state directory is a symlink");
  const wrapper = processIdentity(process.pid);
  if (!wrapper) throw new Error("could not identify the Devin wrapper process");
  const invocation: Invocation = { owner, id: randomUUID(), snapshot: "", created: false, cwd: repo, wrapper };

  const target = join(repo, ".devin");
  try {
    mkdirSync(target, { mode: 0o700 });
    invocation.created = true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    const stat = lstatSync(target);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error("project .devin exists and is not a directory");
  }

  // The marker decides whether this session creates the snapshot or joins one a
  // concurrent invocation already owns. Exclusive writes resolve the race. The
  // created flag follows the mkdir: a directory this invocation made is wholly
  // AgentStart's even when it adopts a marker another merger won.
  const marker = join(target, markerRel);
  const adopted = adoptMarker(target);
  let joined = adopted !== null;
  if (adopted) {
    invocation.snapshot = adopted.id;
  } else {
    invocation.snapshot = invocation.id;
    try {
      writeFileSync(marker, canonicalMarker(invocation.snapshot), { mode: 0o600, flag: "wx" });
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
      const raced = adoptMarker(target);
      if (!raced) throw new Error("project .devin ownership marker changed underneath the invocation");
      invocation.snapshot = raced.id;
      joined = true;
    }
  }

  // Register before writing files so a killed wrapper still leaves a record the
  // periodic cleanup can reconcile.
  const record = invocationPath(stateDir, repo, invocation.id);
  let fd: number;
  try { fd = openSync(record, "wx", 0o600); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") throw new Error(`Devin invocation already recorded: ${record}`);
    throw error;
  }
  try { writeFileSync(fd, JSON.stringify(invocation)); }
  finally { closeSync(fd); }

  // Joined sessions only claim matching content; creating and merging sessions
  // also write the files they are missing. Foreign content is never overwritten.
  const ownedDirs = new Set<string>();
  const claimed: Record<string, string> = { [markerRel]: hashOf(readFileSync(marker)) };
  const conflicts: string[] = [];
  for (const [relative, content] of expectedEntries(role, home)) {
    const result = claimFile(target, relative, content, !joined, ownedDirs);
    if (result === "claimed") claimed[relative] = hashOf(content);
    else if (result === "conflict" && !joined) conflicts.push(relative);
  }
  const gitignore = Buffer.from(renderGitignore(Object.keys(claimed), ownedDirs));
  const gi = claimFile(target, ".gitignore", gitignore, !joined, ownedDirs);
  if (gi === "claimed") claimed[".gitignore"] = hashOf(gitignore);
  else if (gi === "conflict" && !joined) conflicts.push(".gitignore");
  invocation.files = claimed;
  saveInvocation(record, invocation);
  return { repo, record, invocation, conflicts };
}

export function saveInvocation(record: string, invocation: Invocation): void {
  const temp = `${record}.${invocation.id}.tmp`;
  writeFileSync(temp, JSON.stringify(invocation), { mode: 0o600, flag: "wx" });
  renameSync(temp, record);
}

export function shouldPassThrough(args: string[]): boolean {
  if (utilities.has(args[0] ?? "")) return true;
  if (args.some((arg) => ["--help", "-h", "--version", "-V", "--cloud"].includes(arg))) return true;
  return false;
}

function legacyWorktreeResume(cwd: string, home: string, args: string[]): boolean {
  if (!args.some(arg => resumeFlags.has(arg))) return false;
  try {
    const root = realpathSync(execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim());
    if (!root.startsWith(realpathSync(join(home, "worktrees")) + "/")) return false;
    const marker = JSON.parse(readFileSync(join(root, ".devin", "agentstart-owner.json"), "utf8"));
    return marker.owner === "agentstart-devin-worktree-v1" && typeof marker.id === "string";
  } catch { return false; }
}

export async function main(argv: string[], env: NodeJS.ProcessEnv = process.env): Promise<number> {
  if (argv[0] !== "--native" || !argv[1] || !isAbsolute(argv[1]) || argv[2] !== "--") throw new Error("expected --native ABSOLUTE-PATH -- [Devin arguments]");
  const native = resolve(argv[1]);
  if (!statSync(native).isFile()) throw new Error("native Devin CLI is unavailable");
  const args = argv.slice(3);
  let child: ReturnType<typeof Bun.spawn>;
  if (!shouldPassThrough(args) && !legacyWorktreeResume(process.cwd(), env.HOME ?? homedir(), args)) {
    const home = env.HOME ?? homedir();
    const resources = env.AGENTSTART_RESOURCES_ROOT ?? join(home, ".local", "share", "agentstart", "resources");
    const claim = prepareDevinInvocation(process.cwd(), home, resources, invocationDir(env));
    console.error(`Devin session in ${process.cwd()}. Use /prime manually to load AgentStart guidance.`);
    for (const relative of claim.conflicts.slice(0, 5)) console.error(`Kept existing .devin/${relative}; it is not part of the snapshot.`);
    if (claim.conflicts.length > 5) console.error(`Kept ${claim.conflicts.length - 5} more existing .devin entries.`);
    child = Bun.spawn([native, ...args], { cwd: process.cwd(), env: env as Record<string, string>, stdin: "inherit", stdout: "inherit", stderr: "inherit" });
    try {
      const identity = processIdentity(child.pid);
      if (identity) { claim.invocation.child = identity; saveInvocation(claim.record, claim.invocation); }
    } catch (error) {
      // Never leave an unrecorded live child for the periodic job to clean up.
      child.kill("SIGTERM");
      await child.exited;
      throw error;
    }
  } else {
    child = Bun.spawn([native, ...args], { cwd: process.cwd(), env: env as Record<string, string>, stdin: "inherit", stdout: "inherit", stderr: "inherit" });
  }
  const stop = () => child.kill("SIGTERM");
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) process.on(signal, stop);
  try { return await child.exited; }
  finally { for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) process.off(signal, stop); }
}

if (import.meta.main) {
  try { process.exitCode = await main(process.argv.slice(2)); }
  catch (error) { console.error(`AgentStart Devin wrapper: ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; }
}
