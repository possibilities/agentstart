import { afterEach, beforeEach, expect, test } from "bun:test";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { prepareDevinWorktree } from "../scripts/devin-worktree.ts";

let root: string, home: string, repo: string, resources: string, native: string;
const entry = resolve(import.meta.dir, "../scripts/devin-worktree.ts");

function git(cwd: string, args: string[]): string {
  const result = Bun.spawnSync(["git", "-C", cwd, ...args], { stdout: "pipe", stderr: "pipe" });
  if (result.exitCode !== 0) throw new Error(`git ${args[0]}: ${result.stderr.toString()}`);
  return result.stdout.toString().trim();
}
function write(path: string, body: string) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, body); }
function fixture() {
  root = mkdtempSync(join(tmpdir(), "agentstart-devin-test-"));
  home = join(root, "home"); repo = join(root, "repo"); resources = join(root, "resources"); native = join(root, "native-devin");
  mkdirSync(home, { recursive: true }); mkdirSync(repo, { recursive: true });
  git(repo, ["init", "-b", "main"]); git(repo, ["config", "user.name", "Fixture"]); git(repo, ["config", "user.email", "fixture@example.invalid"]);
  write(join(repo, "README.md"), "fixture\n"); git(repo, ["add", "README.md"]); git(repo, ["commit", "-m", "base"]);
  write(join(resources, "roles/default/APPEND_SYSTEM_PROMPT.md"), "# Test prompt\nRemember the result.\n");
  write(join(resources, "roles/default/mcp.json"), JSON.stringify({ mcpServers: { example: { command: "${HOME}/bin/tool", args: ["--flag"] } } }));
  write(join(resources, "roles/default/skills/review/SKILL.md"), "---\nname: review\ndescription: Review test work\n---\nReview changes.\n");
  write(native, "#!/bin/sh\npwd > \"$FAKE_DEVIN_CWD\"\nprintf '%s\\n' \"$@\" > \"$FAKE_DEVIN_ARGS\"\n"); chmodSync(native, 0o755);
}
beforeEach(fixture);
afterEach(() => {
  const paths = git(repo, ["worktree", "list", "--porcelain"]).split("\n").filter((line) => line.startsWith("worktree ")).map((line) => line.slice(9));
  for (const path of paths) if (path.startsWith(join(realpathSync(root), "home", "worktrees") + "/")) git(repo, ["worktree", "remove", "--force", path]);
  rmSync(root, { recursive: true, force: true });
});

test("prepares an ignored Devin role and manual /prime in a new Git worktree", async () => {
  write(join(repo, "not-committed.txt"), "outside the worker");
  const claim = await prepareDevinWorktree(repo, home, resources);
  try {
    expect(claim.sourceDirty).toBe(true);
    expect(claim.worktree).toContain(join(home, "worktrees", "repo", "devin-"));
    expect(readFileSync(join(claim.worktree, ".devin/skills/prime/SKILL.md"), "utf8")).toContain("triggers: [user]");
    expect(readFileSync(join(claim.worktree, ".devin/skills/prime/SKILL.md"), "utf8")).toContain("Remember the result.");
    expect(readFileSync(join(claim.worktree, ".devin/skills/review/SKILL.md"), "utf8")).toContain("Review changes.");
    expect(JSON.parse(readFileSync(join(claim.worktree, ".devin/mcp_config.local.json"), "utf8")).mcpServers.example.command).toBe(join(home, "bin/tool"));
    expect(statSync(join(claim.worktree, ".devin/mcp_config.local.json")).mode & 0o777).toBe(0o600);
    expect(git(claim.worktree, ["status", "--porcelain=v1", "--untracked-files=all"])).toBe("");
    expect(existsSync(join(claim.worktree, "not-committed.txt"))).toBe(false);
    expect(git(repo, ["rev-parse", "HEAD"])).toBe(claim.baseCommit);
  } finally { git(repo, ["worktree", "remove", "--force", claim.worktree]); rmSync(join(repo, "not-committed.txt")); }
});

test("wrapper passes utilities through and runs sessions in a retained worktree", async () => {
  const record = join(root, "record"); const args = join(root, "args");
  const env = { ...process.env, HOME: home, AGENTSTART_RESOURCES_ROOT: resources, FAKE_DEVIN_CWD: record, FAKE_DEVIN_ARGS: args };
  const run = (argv: string[], cwd: string) => Bun.spawnSync([process.execPath, entry, "--native", native, "--", ...argv], { cwd, env, stdout: "pipe", stderr: "pipe" });
  expect(run(["acp"], repo).exitCode).toBe(0);
  expect(readFileSync(record, "utf8").trim()).toBe(realpathSync(repo));
  expect(run(["--version"], repo).exitCode).toBe(0);
  expect(readFileSync(record, "utf8").trim()).toBe(realpathSync(repo));
  const launched = run(["-p", "test task"], repo);
  expect(launched.exitCode).toBe(0);
  const worktree = readFileSync(record, "utf8").trim();
  expect(worktree).toContain(join(realpathSync(root), "home", "worktrees"));
  expect(readFileSync(args, "utf8")).toBe("-p\ntest task\n");
  expect(launched.stderr.toString()).toContain("Use /prime manually");
  expect(run(["-c"], repo).exitCode).toBe(1);
  expect(run(["-c"], worktree).exitCode).toBe(0);
  git(repo, ["worktree", "remove", "--force", worktree]);
});

test("tracked .devin is never overwritten", async () => {
  write(join(repo, ".devin/config.json"), "{}"); git(repo, ["add", ".devin/config.json"]); git(repo, ["commit", "-m", "native config"]);
  expect(prepareDevinWorktree(repo, home, resources)).rejects.toThrow("already owns .devin");
  expect(git(repo, ["worktree", "list", "--porcelain"]).split("\n").filter((line) => line.startsWith("worktree "))).toHaveLength(1);
});

test("the existing harness installer atomically replaces only the native Devin link", () => {
  const vendor = join(home, ".local/share/devin/cli/_versions/current/bin/devin");
  mkdirSync(dirname(vendor), { recursive: true }); copyFileSync(native, vendor); chmodSync(vendor, 0o755);
  const publicBin = join(home, ".local/bin"); mkdirSync(publicBin, { recursive: true });
  const publicDevin = join(publicBin, "devin"); symlinkSync(vendor, publicDevin);
  for (const owner of ["codexnk", "fxnk"]) {
    const installer = join(home, "code", owner, "scripts/install.sh");
    write(installer, "#!/bin/sh\nprintf '%s\\n' /usr/bin/true\n"); chmodSync(installer, 0o755);
  }
  const env = { ...process.env, HOME: home, AGENTSTART_CODE_ROOT: join(home, "code"),
    AGENTSTART_INSTALL_BIN_DIR: publicBin, AGENTSTART_RESOURCES_ROOT: resources,
    FAKE_DEVIN_CWD: join(root, "record"), FAKE_DEVIN_ARGS: join(root, "args") };
  const installer = resolve(import.meta.dir, "../scripts/install-harness-shims");
  const run = () => Bun.spawnSync([installer], { env, stdout: "pipe", stderr: "pipe" });
  expect(run().exitCode).toBe(0);
  expect(readFileSync(publicDevin, "utf8")).toContain("AgentStart-managed Devin worktree shim v1");
  expect(statSync(publicDevin).isFile()).toBe(true);
  expect(readFileSync(vendor, "utf8")).toContain("FAKE_DEVIN_CWD");
  expect(run().exitCode).toBe(0);
  const utility = Bun.spawnSync([publicDevin, "acp"], { cwd: repo, env, stdout: "pipe", stderr: "pipe" });
  expect(utility.exitCode).toBe(0);
  expect(readFileSync(env.FAKE_DEVIN_CWD, "utf8").trim()).toBe(realpathSync(repo));
  const session = Bun.spawnSync([publicDevin, "-p", "test"], { cwd: repo, env, stdout: "pipe", stderr: "pipe" });
  expect(session.exitCode).toBe(0);
  expect(readFileSync(env.FAKE_DEVIN_CWD, "utf8")).toContain("/worktrees/");
  writeFileSync(publicDevin, "#!/bin/sh\n# independent\n");
  expect(run().exitCode).toBe(1);
  expect(readFileSync(publicDevin, "utf8")).toContain("independent");
});
