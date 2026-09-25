import { expect, test } from "bun:test";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { prepareDevinWorktree } from "../scripts/devin-worktree.ts";

const git = (cwd: string, args: string[]): string => {
  const result = Bun.spawnSync(["git", "-C", cwd, ...args], { stdout: "pipe", stderr: "pipe" });
  if (result.exitCode !== 0) throw new Error(`git ${args[0]} failed`);
  return result.stdout.toString().trim();
};

test("real Devin finds the AgentStart Role without the global default plugin", {
  skip: process.env.AGENTSTART_DEVIN_NATIVE_PROBE !== "1", timeout: 60_000,
}, async () => {
  const actualHome = homedir();
  const native = process.env.AGENTSTART_DEVIN_NATIVE ?? join(actualHome, ".local/share/devin/cli/_versions/current/bin/devin");
  const resources = process.env.AGENTSTART_RESOURCES_ROOT ?? join(actualHome, ".local/share/agentstart/resources");
  const sourceCredentials = join(actualHome, ".local/share/devin/credentials.toml");
  if (![native, sourceCredentials, join(resources, "roles/default/APPEND_SYSTEM_PROMPT.md")].every(existsSync)) throw new Error("native Devin login or rendered AgentStart Role is unavailable");
  const root = mkdtempSync(join(tmpdir(), "as-devin-native-"));
  const home = join(root, "home"); const repo = join(root, "repo");
  mkdirSync(home); mkdirSync(repo);
  let worktree: string | undefined;
  try {
    git(repo, ["init", "-b", "main"]);
    git(repo, ["config", "user.name", "Fixture"]); git(repo, ["config", "user.email", "fixture@example.invalid"]);
    writeFileSync(join(repo, "README.md"), "Disposable Devin wrapper check.\n"); git(repo, ["add", "README.md"]); git(repo, ["commit", "-m", "base"]);
    worktree = (await prepareDevinWorktree(repo, home, resources)).worktree;
    const data = join(root, "isolated-data"); const config = join(root, "isolated-config");
    const target = join(data, "devin/credentials.toml"); mkdirSync(dirname(target), { recursive: true, mode: 0o700 });
    mkdirSync(config, { mode: 0o700 }); copyFileSync(sourceCredentials, target); chmodSync(target, 0o600);
    const env = { ...process.env, HOME: actualHome, XDG_DATA_HOME: data, XDG_CONFIG_HOME: config, WINDSURF_API_KEY: "" };
    const run = (args: string[]) => {
      const child = Bun.spawnSync([native, ...args], { cwd: worktree, env, stdout: "pipe", stderr: "pipe", timeout: 20_000 });
      if (child.exitCode !== 0) throw new Error(`Devin ${args.join(" ")} failed: ${child.stderr.toString().slice(0, 300)}`);
      return child.stdout.toString();
    };
    const plugins = run(["plugins", "list"]);
    expect(plugins).not.toContain("default v0.0.0");
    const skills = run(["skills", "list"]);
    expect(skills).toContain("prime");
    expect(skills).toContain("collab");
    const prime = run(["skills", "show", "prime"]);
    expect(prime).toContain("Working with the human");
    const mcp = run(["mcp", "list"]);
    expect(mcp).toContain("agentbrain"); expect(mcp).toContain("gog_mikebannister");
    expect(statSync(join(worktree, ".devin/mcp_config.local.json")).mode & 0o777).toBe(0o600);
    expect(git(worktree, ["status", "--porcelain=v1", "--untracked-files=all"])).toBe("");
  } finally {
    if (worktree) git(repo, ["worktree", "remove", "--force", worktree]);
    rmSync(root, { recursive: true, force: true });
  }
});
