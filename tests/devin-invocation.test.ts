import { afterEach, beforeEach, expect, test } from "bun:test";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { invocationPath, prepareDevinInvocation, type Invocation } from "../scripts/devin-invocation.ts";
import { cleanupDevinInvocations } from "../scripts/devin-cleanup.ts";
import { processIdentity } from "../scripts/devin-process.ts";

let root: string, home: string, repo: string, resources: string, native: string, state: string;
const entry = resolve(import.meta.dir, "../scripts/devin-invocation.ts");

function git(cwd: string, args: string[]): string {
  const result = Bun.spawnSync(["git", "-C", cwd, ...args], { stdout: "pipe", stderr: "pipe" });
  if (result.exitCode !== 0) throw new Error(`git ${args[0]}: ${result.stderr.toString()}`);
  return result.stdout.toString().trim();
}
function write(path: string, body: string) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, body); }
function fixture() {
  root = mkdtempSync(join(tmpdir(), "agentstart-devin-test-"));
  home = join(root, "home"); repo = join(root, "repo"); resources = join(root, "resources"); native = join(root, "native-devin");
  state = join(home, ".local/state/agentstart/devin-invocations");
  mkdirSync(home, { recursive: true }); mkdirSync(repo, { recursive: true });
  git(repo, ["init", "-b", "main"]); git(repo, ["config", "user.name", "Fixture"]); git(repo, ["config", "user.email", "fixture@example.invalid"]);
  write(join(repo, "README.md"), "fixture\n"); git(repo, ["add", "README.md"]); git(repo, ["commit", "-m", "base"]);
  write(join(resources, "roles/default/APPEND_SYSTEM_PROMPT.md"), "# Test prompt\nRemember the result.\n");
  write(join(resources, "roles/default/mcp.json"), JSON.stringify({ mcpServers: { example: { command: "${HOME}/bin/tool", args: ["--flag"] } } }));
  write(join(resources, "roles/default/skills/review/SKILL.md"), "---\nname: review\ndescription: Review test work\n---\nReview changes.\n");
  write(native, "#!/bin/sh\npwd > \"$FAKE_DEVIN_CWD\"\nprintf '%s\\n' \"$@\" > \"$FAKE_DEVIN_ARGS\"\n[ -z \"${FAKE_SLEEP:-}\" ] || sleep \"$FAKE_SLEEP\"\n"); chmodSync(native, 0o755);
}
beforeEach(fixture);
afterEach(() => rmSync(root, { recursive: true, force: true }));

test("prepares Role snapshot in the original repo and retains its edits", () => {
  write(join(repo, "not-committed.txt"), "visible to Devin");
  const head = git(repo, ["rev-parse", "HEAD"]);
  const { invocation, record } = prepareDevinInvocation(repo, home, resources, state);
  expect(readFileSync(join(repo, ".devin/skills/prime/SKILL.md"), "utf8")).toContain("triggers: [user]");
  expect(readFileSync(join(repo, ".devin/skills/review/SKILL.md"), "utf8")).toContain("Review changes.");
  expect(JSON.parse(readFileSync(join(repo, ".devin/mcp_config.local.json"), "utf8")).mcpServers.example.command).toBe(join(home, "bin/tool"));
  expect(statSync(join(repo, ".devin/mcp_config.local.json")).mode & 0o777).toBe(0o600);
  expect(git(repo, ["worktree", "list", "--porcelain"]).split("\n").filter(line => line.startsWith("worktree "))).toHaveLength(1);
  expect(git(repo, ["rev-parse", "HEAD"])).toBe(head);
  expect(readFileSync(join(repo, "not-committed.txt"), "utf8")).toContain("visible");
  expect(JSON.parse(readFileSync(record, "utf8")).id).toBe(invocation.id);
  expect(cleanupDevinInvocations(state)).toBe(0); // wrapper still alive
});

test("wrapper passes utilities through and runs sessions and resumes from original cwd", () => {
  const record = join(root, "record"), args = join(root, "args");
  const env = { ...process.env, HOME: home, AGENTSTART_RESOURCES_ROOT: resources, FAKE_DEVIN_CWD: record, FAKE_DEVIN_ARGS: args };
  const run = (argv: string[], cwd: string) => Bun.spawnSync([process.execPath, entry, "--native", native, "--", ...argv], { cwd, env, stdout: "pipe", stderr: "pipe" });
  expect(run(["acp"], repo).exitCode).toBe(0);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
  expect(run(["--version"], repo).exitCode).toBe(0);
  const subdir = join(repo, "subdir"); mkdirSync(subdir);
  expect(run(["-p", "test task"], subdir).exitCode).toBe(0);
  expect(readFileSync(record, "utf8").trim()).toBe(realpathSync(subdir));
  expect(readFileSync(args, "utf8")).toBe("-p\ntest task\n");
  expect(existsSync(join(repo, ".devin/skills/prime/SKILL.md"))).toBe(true);
  expect(run(["-c"], repo).exitCode).toBe(1); // claim still pending
  expect(cleanupDevinInvocations(state)).toBe(1);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
  expect(run(["-c"], repo).exitCode).toBe(0);
  expect(cleanupDevinInvocations(state)).toBe(1);
});

test("existing marked worktrees can still resume without creating a new snapshot", () => {
  const legacy = join(home, "worktrees", "repo", "devin-legacy", "repo");
  mkdirSync(dirname(legacy), { recursive: true });
  git(repo, ["worktree", "add", "--detach", legacy]);
  write(join(legacy, ".devin/agentstart-owner.json"), JSON.stringify({ owner: "agentstart-devin-worktree-v1", id: "legacy" }));
  const env = { ...process.env, HOME: home, AGENTSTART_RESOURCES_ROOT: resources,
    FAKE_DEVIN_CWD: join(root, "record"), FAKE_DEVIN_ARGS: join(root, "args") };
  try {
    const result = Bun.spawnSync([process.execPath, entry, "--native", native, "--", "-c"], { cwd: legacy, env, stdout: "pipe", stderr: "pipe" });
    expect(result.exitCode).toBe(0);
    expect(readFileSync(env.FAKE_DEVIN_CWD, "utf8").trim()).toBe(realpathSync(legacy));
    expect(existsSync(invocationPath(state, realpathSync(legacy)))).toBe(false);
    expect(readFileSync(join(legacy, ".devin/agentstart-owner.json"), "utf8")).toContain("worktree-v1");
  } finally { git(repo, ["worktree", "remove", "--force", legacy]); }
});

test("live child protects the snapshot; PID reuse does not", async () => {
  const env = { ...process.env, HOME: home, AGENTSTART_RESOURCES_ROOT: resources, FAKE_DEVIN_CWD: join(root, "record"), FAKE_DEVIN_ARGS: join(root, "args"), FAKE_SLEEP: "1" };
  const child = Bun.spawn([process.execPath, entry, "--native", native, "--", "-p", "task"], { cwd: repo, env, stdout: "pipe", stderr: "pipe" });
  try {
    for (let i = 0; i < 100 && !existsSync(invocationPath(state, realpathSync(repo))); i++) await Bun.sleep(10);
    expect(existsSync(join(repo, ".devin"))).toBe(true);
    expect(cleanupDevinInvocations(state)).toBe(0);
    expect(await child.exited).toBe(0);
    const record = invocationPath(state, realpathSync(repo));
    const invocation = JSON.parse(readFileSync(record, "utf8")) as Invocation;
    expect(invocation.child?.pid).toBeGreaterThan(0);
    expect(invocation.child?.started).toMatch(/^\d+\.\d{6}$/);
    // Both PIDs may now designate unrelated new processes; their start times
    // differ, so the old session is still ended.
    expect(cleanupDevinInvocations(state, pid => ({ pid, started: "1.000001" }))).toBe(1);
    expect(existsSync(join(repo, ".devin"))).toBe(false);
  } finally { if (child.exitCode === null) { child.kill(); await child.exited; } }
});

test("preserves foreign and changed project content", () => {
  write(join(repo, ".devin/config.json"), "{}");
  expect(() => prepareDevinInvocation(repo, home, resources, state)).toThrow("already contains .devin");
  rmSync(join(repo, ".devin"), { recursive: true });
  prepareDevinInvocation(repo, home, resources, state);
  write(join(repo, ".devin/skills/review/SKILL.md"), "Human changed this.\n");
  write(join(repo, ".devin/notes.txt"), "Human note.\n");
  expect(cleanupDevinInvocations(state, () => null)).toBe(1);
  expect(readFileSync(join(repo, ".devin/skills/review/SKILL.md"), "utf8")).toContain("Human changed");
  expect(readFileSync(join(repo, ".devin/notes.txt"), "utf8")).toContain("Human note");
});

test("cleanup refuses a replaced ownership marker and does not follow a substituted skill directory", () => {
  const { record, invocation } = prepareDevinInvocation(repo, home, resources, state);
  const outside = join(root, "outside");
  write(join(outside, "SKILL.md"), "Review changes.\n");
  rmSync(join(repo, ".devin/skills/review"), { recursive: true });
  symlinkSync(outside, join(repo, ".devin/skills/review"));
  cleanupDevinInvocations(state, () => null);
  expect(readFileSync(join(outside, "SKILL.md"), "utf8")).toBe("Review changes.\n");
  expect(existsSync(join(repo, ".devin/skills/review"))).toBe(true);
  expect(existsSync(record)).toBe(false);
  // A foreign marker never authorizes deletion of even unchanged files.
  rmSync(join(repo, ".devin"), { recursive: true });
  const second = prepareDevinInvocation(repo, home, resources, state);
  write(join(repo, ".devin/agentstart-owner.json"), JSON.stringify({ owner: "foreign", id: second.invocation.id }));
  expect(cleanupDevinInvocations(state, () => null)).toBe(0);
  expect(existsSync(second.record)).toBe(true);
  expect(existsSync(join(repo, ".devin/config.json"))).toBe(true);
});

test("cleanup removes a partial marked snapshot after a killed wrapper", () => {
  const { record, invocation } = prepareDevinInvocation(repo, home, resources, state);
  writeFileSync(record, JSON.stringify({ ...invocation, files: undefined }));
  expect(cleanupDevinInvocations(state, () => null)).toBe(1);
  expect(existsSync(join(repo, ".devin"))).toBe(false);
});

test("harness installer replaces only the native link or its own old marker", () => {
  const vendor = join(home, ".local/share/devin/cli/_versions/current/bin/devin");
  mkdirSync(dirname(vendor), { recursive: true }); copyFileSync(native, vendor); chmodSync(vendor, 0o755);
  const publicBin = join(home, ".local/bin"); mkdirSync(publicBin, { recursive: true });
  const publicDevin = join(publicBin, "devin"); symlinkSync(vendor, publicDevin);
  for (const tool of ["codexnk", "fxnk"]) {
    const installer = join(home, "code", tool, "scripts/install.sh");
    write(installer, "#!/bin/sh\nprintf '%s\\n' /usr/bin/true\n"); chmodSync(installer, 0o755);
  }
  const env = { ...process.env, HOME: home, AGENTSTART_CODE_ROOT: join(home, "code"),
    AGENTSTART_INSTALL_BIN_DIR: publicBin, AGENTSTART_RESOURCES_ROOT: resources,
    FAKE_DEVIN_CWD: join(root, "record"), FAKE_DEVIN_ARGS: join(root, "args") };
  const installer = resolve(import.meta.dir, "../scripts/install-harness-shims");
  const run = () => Bun.spawnSync([installer], { env, stdout: "pipe", stderr: "pipe" });
  expect(run().exitCode).toBe(0);
  expect(readFileSync(publicDevin, "utf8")).toContain("AgentStart-managed Devin invocation shim v1");
  expect(run().exitCode).toBe(0);
  expect(Bun.spawnSync([publicDevin, "acp"], { cwd: repo, env }).exitCode).toBe(0);
  expect(Bun.spawnSync([publicDevin, "-p", "test"], { cwd: repo, env }).exitCode).toBe(0);
  expect(readFileSync(env.FAKE_DEVIN_CWD, "utf8").trim()).toBe(realpathSync(repo));
  expect(cleanupDevinInvocations(state)).toBe(1);
  writeFileSync(publicDevin, "#!/bin/sh\n# AgentStart-managed Devin worktree shim v1\n");
  expect(run().exitCode).toBe(0);
  writeFileSync(publicDevin, "#!/bin/sh\n# independent\n");
  expect(run().exitCode).toBe(1);
  expect(readFileSync(publicDevin, "utf8")).toContain("independent");
});

test("libproc identity includes kernel microseconds", () => {
  expect(processIdentity(process.pid)?.started).toMatch(/^\d+\.\d{6}$/);
  expect(processIdentity(2147483647)).toBeNull();
});
