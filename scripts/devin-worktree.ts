#!/usr/bin/env bun
/** One Devin CLI session in a fresh, role-equipped Git worktree. Utilities and ACP pass through unchanged. */
import { execFile, execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { homedir } from "node:os";

const utilities = new Set(["acp", "auth", "mcp", "models", "skills", "rules", "plugins", "version", "doctor", "update", "setup", "cloud", "ssh", "forward", "worker", "uninstall", "help", "sandbox", "airgap"]);
const resumeFlags = new Set(["-c", "--continue", "-r", "--resume"]);
const skillName = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const mcpName = /^[a-z][a-z0-9_-]*$/;

export type Prepared = { repo: string; worktree: string; branch: string; baseCommit: string; sourceDirty: boolean };

function git(cwd: string, args: string[]): Promise<string> {
  return new Promise((resolveResult, reject) => execFile("git", ["-C", cwd, ...args], { timeout: 20_000, maxBuffer: 1_000_000 }, (error, stdout) =>
    error ? reject(new Error(`Git ${args[0]} failed; inspect the repository`)) : resolveResult(stdout.trim())));
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

function renderRole(worktree: string, role: string, home: string, id: string): void {
  const target = join(worktree, ".devin");
  if (existsSync(target)) throw new Error("source branch already contains .devin; refusing to overwrite it");
  mkdirSync(join(target, "skills"), { recursive: true, mode: 0o700 });
  writeFileSync(join(target, ".gitignore"), "*\n", { mode: 0o600 });
  writeFileSync(join(target, "agentstart-owner.json"), JSON.stringify({ owner: "agentstart-devin-worktree-v1", id }), { mode: 0o600 });
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
}

export async function prepareDevinWorktree(cwd: string, home: string, resourcesRoot: string): Promise<Prepared> {
  const repo = realpathSync(await git(cwd, ["rev-parse", "--show-toplevel"]));
  const baseCommit = await git(repo, ["rev-parse", "--verify", "HEAD^{commit}"]);
  if (!/^[0-9a-f]{40,64}$/.test(baseCommit)) throw new Error("Git HEAD did not resolve to a commit");
  if (await git(repo, ["ls-tree", "--name-only", baseCommit, ".devin"]))
    throw new Error("source branch already owns .devin; start with an unconfigured worktree or use native Devin explicitly");
  const role = safeRole(resourcesRoot);
  const sourceDirty = Boolean(await git(repo, ["status", "--porcelain=v1", "--untracked-files=normal"]));
  const id = randomUUID();
  const name = basename(repo);
  const worktree = join(home, "worktrees", name, `devin-${id}`, name);
  const branch = `agentstart-devin-${id}`;
  mkdirSync(dirname(worktree), { recursive: true, mode: 0o700 });
  await git(repo, ["worktree", "add", "-b", branch, worktree, baseCommit]);
  renderRole(worktree, role, home, id);
  if (await git(worktree, ["status", "--porcelain=v1", "--untracked-files=all"]))
    throw new Error("Devin Role files are visible to Git; inspect the retained worktree");
  return { repo, worktree, branch, baseCommit, sourceDirty };
}

function ownedWorktree(cwd: string, home: string): string | null {
  try {
    const root = execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
    const marker = JSON.parse(readFileSync(join(root, ".devin", "agentstart-owner.json"), "utf8")) as { owner?: string; id?: string };
    return marker.owner === "agentstart-devin-worktree-v1" && typeof marker.id === "string" && realpathSync(root).startsWith(realpathSync(join(home, "worktrees")) + "/") ? root : null;
  } catch { return null; }
}

export function shouldPassThrough(args: string[]): boolean {
  if (utilities.has(args[0] ?? "")) return true;
  if (args.some((arg) => ["--help", "-h", "--version", "-V", "--cloud"].includes(arg))) return true;
  return false;
}

export async function main(argv: string[], env: NodeJS.ProcessEnv = process.env): Promise<number> {
  if (argv[0] !== "--native" || !argv[1] || !isAbsolute(argv[1]) || argv[2] !== "--") throw new Error("expected --native ABSOLUTE-PATH -- [Devin arguments]");
  const native = resolve(argv[1]);
  if (!statSync(native).isFile()) throw new Error("native Devin CLI is unavailable");
  const args = argv.slice(3);
  let cwd = process.cwd();
  if (!shouldPassThrough(args)) {
    if (args.some((arg) => resumeFlags.has(arg))) {
      cwd = ownedWorktree(cwd, env.HOME ?? homedir()) ?? (() => { throw new Error("resume inside its AgentStart-owned Devin worktree; use the native CLI explicitly to bypass"); })();
    } else {
      const home = env.HOME ?? homedir();
      const resources = env.AGENTSTART_RESOURCES_ROOT ?? join(home, ".local", "share", "agentstart", "resources");
      const claim = await prepareDevinWorktree(cwd, home, resources);
      cwd = claim.worktree;
      console.error(`Devin worktree: ${claim.worktree}\nBranch: ${claim.branch}${claim.sourceDirty ? "\nSource checkout is dirty; uncommitted changes were not copied." : ""}\nUse /prime manually to load AgentStart guidance.`);
    }
  }
  const child = Bun.spawn([native, ...args], { cwd, env: env as Record<string, string>, stdin: "inherit", stdout: "inherit", stderr: "inherit" });
  const stop = () => child.kill("SIGTERM");
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) process.on(signal, stop);
  try { return await child.exited; }
  finally { for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) process.off(signal, stop); }
}

if (import.meta.main) {
  try { process.exitCode = await main(process.argv.slice(2)); }
  catch (error) { console.error(`AgentStart Devin wrapper: ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; }
}
