#!/usr/bin/env bun
/** Terminal Devin sessions run in place with a disposable, Role-equipped .devin. */
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { cpSync, existsSync, lstatSync, mkdirSync, openSync, closeSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync, renameSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { homedir } from "node:os";
import { processIdentity, type ProcessIdentity } from "./devin-process.ts";

const utilities = new Set(["acp", "auth", "mcp", "models", "skills", "rules", "plugins", "version", "doctor", "update", "setup", "cloud", "ssh", "forward", "worker", "uninstall", "help", "sandbox", "airgap"]);
const resumeFlags = new Set(["-c", "--continue", "-r", "--resume"]);
const skillName = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const mcpName = /^[a-z][a-z0-9_-]*$/;
export const owner = "agentstart-devin-invocation-v1";

export type Invocation = { owner: typeof owner; id: string; cwd: string; wrapper: ProcessIdentity; child?: ProcessIdentity; files?: Record<string, string> };
export function invocationDir(env: NodeJS.ProcessEnv = process.env): string {
  const home = env.HOME ?? homedir();
  // A fixed home-relative path lets the LaunchAgent see every terminal invocation,
  // even when a caller overrides XDG_STATE_HOME for an unrelated tool.
  return join(home, ".local", "state", "agentstart", "devin-invocations");
}
export function invocationPath(dir: string, cwd: string): string {
  return join(dir, createHash("sha256").update(cwd).digest("hex") + ".json");
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

function snapshotFiles(target: string): Record<string, string> {
  const files: Record<string, string> = {};
  const visit = (dir: string, prefix: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      const path = join(dir, entry.name);
      if (entry.isDirectory()) visit(path, relative);
      else if (entry.isFile()) files[relative] = createHash("sha256").update(readFileSync(path)).digest("hex");
      else throw new Error(`unsupported Role file: ${relative}`);
    }
  };
  visit(target, "");
  return files;
}

function renderGitignore(target: string): string {
  const entries = readdirSync(target, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  const lines = entries.map((entry) => `/${entry.name}${entry.isDirectory() ? "/" : ""}`);
  return `# AgentStart Devin invocation snapshot.\n/.gitignore\n${lines.join("\n")}\n`;
}

function renderRole(repo: string, role: string, home: string, id: string): Record<string, string> {
  const target = join(repo, ".devin");
  if (existsSync(target) || lstatExists(target)) throw new Error("project already contains .devin; refusing to overwrite it");
  mkdirSync(target, { mode: 0o700 });
  writeFileSync(join(target, "agentstart-owner.json"), JSON.stringify({ owner, id }), { mode: 0o600 });
  mkdirSync(join(target, "skills"), { mode: 0o700 });
  writeFileSync(join(target, "config.json"), JSON.stringify({ read_config_from: {
    agents_standard: true, cursor: false, windsurf: false, claude: false, copilot: false, opencode: false, zed: false,
  } }, null, 2) + "\n", { mode: 0o600 });
  writeFileSync(join(target, "mcp_config.local.json"), renderMcp(role, home), { mode: 0o600 });
  const sourceSkills = join(role, "skills");
  for (const name of readdirSync(sourceSkills)) {
    if (!skillName.test(name) || name === "prime") throw new Error(`unsupported or reserved Role skill name: ${name}`);
    const source = join(sourceSkills, name);
    if (!statSync(source).isDirectory() || !statSync(join(source, "SKILL.md")).isFile()) throw new Error(`invalid Role skill: ${name}`);
    cpSync(source, join(target, "skills", name), { recursive: true, dereference: true });
  }
  const prime = join(target, "skills", "prime");
  mkdirSync(prime, { mode: 0o700 });
  const instructions = readFileSync(join(role, "APPEND_SYSTEM_PROMPT.md"), "utf8");
  writeFileSync(join(prime, "SKILL.md"), `---\nname: prime\ndescription: Load AgentStart's working instructions when explicitly invoked\ntriggers: [user]\n---\n\n${instructions}\n`, { mode: 0o600 });
  writeFileSync(join(target, ".gitignore"), renderGitignore(target), { mode: 0o600 });
  return snapshotFiles(target);
}

function lstatExists(path: string): boolean { try { lstatSync(path); return true; } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return false; throw error; } }

export function prepareDevinInvocation(cwd: string, home: string, resourcesRoot: string, stateDir: string): { repo: string; record: string; invocation: Invocation } {
  const repo = realpathSync(execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim());
  const role = safeRole(resourcesRoot);
  if (lstatExists(join(repo, ".devin"))) throw new Error("project already contains .devin; refusing to overwrite it");
  mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  if (lstatSync(stateDir).isSymbolicLink()) throw new Error("Devin state directory is a symlink");
  const record = invocationPath(stateDir, repo);
  const wrapper = processIdentity(process.pid);
  if (!wrapper) throw new Error("could not identify the Devin wrapper process");
  const invocation: Invocation = { owner, id: randomUUID(), cwd: repo, wrapper };
  let fd: number;
  try { fd = openSync(record, "wx", 0o600); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") throw new Error(`Devin invocation already recorded for ${repo}; wait for cleanup or inspect ${record}`);
    throw error;
  }
  try { writeFileSync(fd, JSON.stringify(invocation)); }
  finally { closeSync(fd); }
  invocation.files = renderRole(repo, role, home, invocation.id);
  saveInvocation(record, invocation);
  return { repo, record, invocation };
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
