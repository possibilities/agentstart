import { afterEach, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import {
  AgentTracker,
  ReapTracker,
  candidateFromWorktree,
} from "../skills/supervisor/scripts/watch.ts";
import { listLiveWorktrees, normalizePath } from "../skills/supervisor/scripts/git.ts";
import {
  WorktreeDiscovery,
  findRepositories,
  scanRepository,
  surveyRepository,
} from "../skills/supervisor/scripts/worktrees.ts";
import { buildRoster } from "../skills/supervisor/scripts/roster.ts";
import { ownerOf } from "../skills/supervisor/scripts/ade.ts";

const root = resolve(import.meta.dir, "..");
const watchScript = join(root, "skills", "supervisor", "scripts", "watch.ts");
const integrateScript = join(root, "skills", "supervisor", "scripts", "integrate.ts");
const reapScript = join(root, "skills", "supervisor", "scripts", "reap.ts");
const statusScript = join(root, "skills", "supervisor", "scripts", "status.ts");
const temporaryPaths: string[] = [];

afterEach(() => {
  for (const path of temporaryPaths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function temporaryRoot(): string {
  const path = mkdtempSync(join(tmpdir(), "agentstart-supervisor."));
  temporaryPaths.push(path);
  return path;
}

function git(cwd: string, ...args: string[]): string {
  const result = Bun.spawnSync(["git", "-C", cwd, ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`git ${args.join(" ")} failed: ${result.stderr.toString()}`);
  }
  return result.stdout.toString().trim();
}

interface Fixture {
  root: string;
  projectsRoot: string;
  main: string;
  worktree: string;
  remote: string;
  workerHead: string;
}

function createFixture(diverge = false): Fixture {
  const fixtureRoot = temporaryRoot();
  const projectsRoot = join(fixtureRoot, "projects");
  const main = join(projectsRoot, "project");
  const worktree = join(fixtureRoot, "worktrees", "peer");
  const remote = join(fixtureRoot, "origin.git");
  mkdirSync(main, { recursive: true });
  mkdirSync(join(fixtureRoot, "worktrees"), { recursive: true });

  git(main, "init", "--initial-branch=main");
  git(main, "config", "user.name", "Supervisor Test");
  git(main, "config", "user.email", "supervisor@example.invalid");
  writeFileSync(join(main, "base.txt"), "base\n");
  git(main, "add", "base.txt");
  git(main, "commit", "-m", "base");
  git(fixtureRoot, "init", "--bare", "--initial-branch=main", remote);
  git(main, "remote", "add", "origin", remote);
  git(main, "push", "-u", "origin", "main");
  git(main, "worktree", "add", "-b", "worktree/peer", worktree, "main");

  if (diverge) {
    writeFileSync(join(main, "main.txt"), "main advanced\n");
    git(main, "add", "main.txt");
    git(main, "commit", "-m", "advance main");
    git(main, "push", "origin", "main");
  }

  writeFileSync(join(worktree, "worker.txt"), "worker result\n");
  git(worktree, "add", "worker.txt");
  git(worktree, "commit", "-m", "worker result");
  const workerHead = git(worktree, "rev-parse", "HEAD");
  return { root: fixtureRoot, projectsRoot, main, worktree, remote, workerHead };
}

async function run(args: string[], env: Record<string, string> = {}): Promise<{
  exitCode: number;
  stdout: string;
  stderr: string;
}> {
  const child = Bun.spawn(args, {
    cwd: root,
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  return { exitCode, stdout, stderr };
}

async function readLine(stream: ReadableStream<Uint8Array>, timeoutMs = 2_000): Promise<string> {
  const reader = stream.getReader();
  let deadline: ReturnType<typeof setTimeout> | null = null;
  const read = async () => {
    let buffered = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) throw new Error("stream ended before a line arrived");
      buffered += new TextDecoder().decode(value);
      const newline = buffered.indexOf("\n");
      if (newline >= 0) return buffered.slice(0, newline);
    }
  };
  try {
    return await Promise.race([
      read(),
      new Promise<string>((_resolve, reject) => {
        deadline = setTimeout(() => reject(new Error("timed out waiting for watcher output")), timeoutMs);
      }),
    ]);
  } finally {
    if (deadline) clearTimeout(deadline);
    void reader.cancel();
  }
}

/**
 * A reader that survives more than one line, for tests that watch a stream
 * react to something they do between reads. `readLine` cancels its stream on
 * the way out, which is right for a single expected line and wrong here.
 */
/** Every emitted object, and the roster the watcher always opens with. */
function emitted(stdout: string): Array<Record<string, unknown>> {
  return stdout
    .trim()
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => JSON.parse(line));
}

function candidates(stdout: string): Array<Record<string, unknown>> {
  return emitted(stdout).filter((record) => record["type"] !== "roster");
}

function lineReader(stream: ReadableStream<Uint8Array>) {
  const reader = stream.getReader();
  let buffered = "";

  const read = async (): Promise<string> => {
    while (true) {
      const newline = buffered.indexOf("\n");
      if (newline >= 0) {
        const line = buffered.slice(0, newline);
        buffered = buffered.slice(newline + 1);
        if (line.trim() !== "") return line;
        continue;
      }
      const { value, done } = await reader.read();
      if (done) throw new Error("stream ended before a line arrived");
      buffered += new TextDecoder().decode(value);
    }
  };

  return {
    async next(timeoutMs = 10_000): Promise<string> {
      let deadline: ReturnType<typeof setTimeout> | null = null;
      try {
        return await Promise.race([
          read(),
          new Promise<string>((_resolve, reject) => {
            deadline = setTimeout(() => reject(new Error("timed out waiting for watcher output")), timeoutMs);
          }),
        ]);
      } finally {
        if (deadline) clearTimeout(deadline);
      }
    },
    release(): void {
      void reader.cancel();
    },
  };
}

describe("AgentTracker", () => {
  const row = (status: string) => ({
    pane_id: "w1:p1",
    agent_status: status,
    cwd: "/tmp/example",
    agent_session: { value: "session-1", agent: "codex" },
  });

  test("discovers an already-idle peer once during reconciliation", () => {
    const tracker = new AgentTracker();
    expect(tracker.reconcile([row("idle")])).toMatchObject([{ reason: "startup" }]);
    expect(tracker.reconcile([row("idle")])).toEqual([]);
  });

  test("emits only a working to stopped transition", () => {
    const tracker = new AgentTracker();
    tracker.reconcile([row("working")]);
    expect(tracker.handleEvent("pane_updated", { pane: row("blocked") })).toEqual([]);
    tracker.handleEvent("pane_updated", { pane: row("working") });
    expect(tracker.handleEvent("pane_updated", { pane: row("idle") })).toMatchObject([
      { reason: "transition" },
    ]);
    expect(tracker.handleEvent("pane_updated", { pane: row("idle") })).toEqual([]);
  });
});

test("the reap tracker waits for agent exit and workspace closure", () => {
  const tracker = new ReapTracker();
  const agent = {
    pane_id: "w1:p1",
    workspace_id: "w1",
    agent_status: "idle",
    cwd: "/tmp/worktree",
    agent_session: { value: "session-1", agent: "codex" },
  };
  tracker.reconcile([agent]);
  expect(
    tracker.handleEvent("pane_agent_detected", {
      pane_id: "w1:p1",
      released: true,
      final_status: "idle",
    }),
  ).toEqual([]);
  expect(
    tracker.handleEvent("workspace_closed", {
      workspace_id: "w1",
      workspace: {
        workspace_id: "w1",
        worktree: { checkout_path: "/tmp/worktree", is_linked_worktree: true },
      },
    }),
  ).toMatchObject([{ workspace_id: "w1", agents: [{ pane_id: "w1:p1" }] }]);
});

test("the watcher reconciles through a fake Herdr socket and finds an arbitrary worktree", async () => {
  const fixture = createFixture();
  const socketPath = join(fixture.root, "herdr.sock");
  const buffers = new WeakMap<object, string>();
  const listener = Bun.listen({
    unix: socketPath,
    socket: {
      data(socket, chunk) {
        const buffered = (buffers.get(socket) ?? "") + new TextDecoder().decode(chunk);
        const newline = buffered.indexOf("\n");
        if (newline < 0) {
          buffers.set(socket, buffered);
          return;
        }
        const request = JSON.parse(buffered.slice(0, newline));
        if (request.method === "events.subscribe") {
          socket.write(`${JSON.stringify({ id: request.id, result: { type: "subscription_started" } })}\n`);
        } else if (request.method === "agent.list") {
          socket.write(
            `${JSON.stringify({
              id: request.id,
              result: {
                agents: [
                  {
                    pane_id: "w9:p1",
                    agent_status: "idle",
                    cwd: fixture.worktree,
                    agent_session: { value: "peer-session", agent: "codex" },
                  },
                ],
              },
            })}\n`,
          );
          socket.end();
        }
      },
    },
  });

  const environment = { ...process.env } as Record<string, string>;
  delete environment.HERDR_PANE_ID;
  const result = await run(
    [
      process.execPath,
      watchScript,
      "--once",
      "--no-discover",
      "--socket",
      socketPath,
      "--project-root",
      fixture.projectsRoot,
    ],
    environment,
  );
  listener.stop(true);

  expect(result.exitCode).toBe(0);
  expect(result.stderr).toBe("");
  const candidate = JSON.parse(result.stdout.trim());
  expect(candidate).toMatchObject({
    type: "merge_candidate",
    reason: "startup",
    session_id: "peer-session",
    worktree: normalizePath(fixture.worktree),
    main_worktree: normalizePath(fixture.main),
    head: fixture.workerHead,
    commits_ahead: 1,
    clean: true,
  });
});

test("the long-lived watcher emits an event that arrives during bootstrap reconciliation", async () => {
  const fixture = createFixture();
  const socketPath = join(fixture.root, "herdr-events.sock");
  const buffers = new WeakMap<object, string>();
  let subscriptionSocket: { write(data: string): number } | null = null;
  const listener = Bun.listen({
    unix: socketPath,
    socket: {
      data(socket, chunk) {
        const buffered = (buffers.get(socket) ?? "") + new TextDecoder().decode(chunk);
        const newline = buffered.indexOf("\n");
        if (newline < 0) {
          buffers.set(socket, buffered);
          return;
        }
        const request = JSON.parse(buffered.slice(0, newline));
        const agent = {
          pane_id: "w8:p1",
          agent_status: "working",
          cwd: fixture.worktree,
          agent_session: { value: "event-peer-session", agent: "claude" },
        };
        if (request.method === "events.subscribe") {
          subscriptionSocket = socket;
          socket.write(`${JSON.stringify({ id: request.id, result: { type: "subscription_started" } })}\n`);
        } else if (request.method === "agent.list") {
          subscriptionSocket?.write(
            `${JSON.stringify({
              event: "pane_updated",
              data: { pane: { pane_id: "w8:p1", agent_status: "idle" } },
            })}\n`,
          );
          socket.write(`${JSON.stringify({ id: request.id, result: { agents: [agent] } })}\n`);
          socket.end();
        }
      },
    },
  });

  const child = Bun.spawn(
    [
      process.execPath,
      watchScript,
      "--no-discover",
      "--socket",
      socketPath,
      "--project-root",
      fixture.projectsRoot,
    ],
    { cwd: root, env: process.env, stdout: "pipe", stderr: "pipe" },
  );
  const line = await readLine(child.stdout);
  child.kill("SIGTERM");
  await child.exited;
  listener.stop(true);

  expect(JSON.parse(line)).toMatchObject({
    type: "merge_candidate",
    reason: "transition",
    session_id: "event-peer-session",
    head: fixture.workerHead,
  });
});

test("the watcher wakes with a reap candidate after agent exit and workspace closure", async () => {
  const fixture = createFixture();
  const socketPath = join(fixture.root, "herdr-reap.sock");
  const buffers = new WeakMap<object, string>();
  let subscriptionSocket: { write(data: string): number } | null = null;
  const listener = Bun.listen({
    unix: socketPath,
    socket: {
      data(socket, chunk) {
        const buffered = (buffers.get(socket) ?? "") + new TextDecoder().decode(chunk);
        const newline = buffered.indexOf("\n");
        if (newline < 0) {
          buffers.set(socket, buffered);
          return;
        }
        const request = JSON.parse(buffered.slice(0, newline));
        const agent = {
          pane_id: "w7:p1",
          workspace_id: "w7",
          agent_status: "working",
          cwd: fixture.worktree,
          agent_session: { value: "reap-peer-session", agent: "claude" },
        };
        if (request.method === "events.subscribe") {
          subscriptionSocket = socket;
          socket.write(`${JSON.stringify({ id: request.id, result: { type: "subscription_started" } })}\n`);
        } else if (request.method === "agent.list") {
          socket.write(`${JSON.stringify({ id: request.id, result: { agents: [agent] } })}\n`);
          socket.end();
          setTimeout(() => {
            subscriptionSocket?.write(
              `${JSON.stringify({
                event: "pane_agent_detected",
                data: { pane_id: "w7:p1", released: true, final_status: "idle" },
              })}\n`,
            );
            subscriptionSocket?.write(
              `${JSON.stringify({
                event: "workspace_closed",
                data: {
                  workspace_id: "w7",
                  workspace: {
                    workspace_id: "w7",
                    worktree: {
                      repo_key: join(fixture.main, ".git"),
                      repo_name: "project",
                      repo_root: fixture.main,
                      checkout_path: fixture.worktree,
                      is_linked_worktree: true,
                    },
                  },
                },
              })}\n`,
            );
          }, 10);
        }
      },
    },
  });

  const child = Bun.spawn(
    [
      process.execPath,
      watchScript,
      "--no-discover",
      "--socket",
      socketPath,
      "--project-root",
      fixture.projectsRoot,
    ],
    { cwd: root, env: process.env, stdout: "pipe", stderr: "pipe" },
  );
  const line = await readLine(child.stdout);
  child.kill("SIGTERM");
  await child.exited;
  listener.stop(true);

  expect(JSON.parse(line)).toMatchObject({
    type: "reap_candidate",
    workspace_id: "w7",
    branch: "worktree/peer",
    head: fixture.workerHead,
    agents: [
      { harness: "claude", session_id: "reap-peer-session", pane_id: "w7:p1" },
    ],
  });
});

test("the integrator fast-forwards local main and pushes that exact commit", async () => {
  const fixture = createFixture();
  writeFileSync(join(fixture.main, "human-note.txt"), "preserve me\n");
  const result = await run([
    process.execPath,
    integrateScript,
    "--source",
    fixture.worktree,
    "--expected-head",
    fixture.workerHead,
    "--project-root",
    fixture.projectsRoot,
  ]);

  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toMatchObject({
    ok: true,
    code: "integrated_and_pushed",
    main_head: fixture.workerHead,
    remote_head: fixture.workerHead,
  });
  expect(git(fixture.main, "rev-parse", "main")).toBe(fixture.workerHead);
  expect(git(fixture.root, "--git-dir", fixture.remote, "rev-parse", "main")).toBe(fixture.workerHead);
  expect(git(fixture.main, "status", "--porcelain")).toContain("?? human-note.txt");
});

test("the integrator rejects approval for a head that changed", async () => {
  const fixture = createFixture();
  writeFileSync(join(fixture.worktree, "later.txt"), "later\n");
  git(fixture.worktree, "add", "later.txt");
  git(fixture.worktree, "commit", "-m", "later work");
  const result = await run([
    process.execPath,
    integrateScript,
    "--source",
    fixture.worktree,
    "--expected-head",
    fixture.workerHead,
    "--project-root",
    fixture.projectsRoot,
  ]);

  expect(result.exitCode).toBe(10);
  expect(JSON.parse(result.stdout)).toMatchObject({ ok: false, code: "source_head_changed" });
});

test("the integrator returns divergent work to the peer instead of merging", async () => {
  const fixture = createFixture(true);
  const mainBefore = git(fixture.main, "rev-parse", "main");
  const result = await run([
    process.execPath,
    integrateScript,
    "--source",
    fixture.worktree,
    "--expected-head",
    fixture.workerHead,
    "--project-root",
    fixture.projectsRoot,
  ]);

  expect(result.exitCode).toBe(30);
  expect(JSON.parse(result.stdout)).toMatchObject({
    ok: false,
    code: "source_needs_reconciliation",
    main_head: mainBefore,
  });
  expect(git(fixture.main, "rev-parse", "main")).toBe(mainBefore);
});

test("the reaper removes a closed clean worktree, preserves its branch, and writes receipts", async () => {
  const fixture = createFixture();
  const normalizedWorktree = normalizePath(fixture.worktree);
  const log = join(fixture.root, "state", "reaped.jsonl");
  const agent = JSON.stringify({ harness: "codex", session_id: "session-42", pane_id: "w4:p2" });
  const result = await run([
    process.execPath,
    reapScript,
    "--worktree",
    fixture.worktree,
    "--expected-branch",
    "worktree/peer",
    "--expected-head",
    fixture.workerHead,
    "--workspace-id",
    "w4",
    "--agent-json",
    agent,
    "--project-root",
    fixture.projectsRoot,
    "--log",
    log,
  ]);

  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toMatchObject({
    ok: true,
    code: "worktree_reaped",
    branch: "worktree/peer",
    head: fixture.workerHead,
  });
  expect(existsSync(fixture.worktree)).toBe(false);
  expect(git(fixture.main, "rev-parse", "refs/heads/worktree/peer")).toBe(fixture.workerHead);
  const records = readFileSync(log, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  expect(records.map((record) => record.event)).toEqual(["reap_started", "reaped"]);
  expect(records[1]).toMatchObject({
    workspace_id: "w4",
    worktree: normalizedWorktree,
    branch: "worktree/peer",
    head: fixture.workerHead,
    agents: [{ harness: "codex", session_id: "session-42", pane_id: "w4:p2" }],
  });
});

test("the reaper removes an unowned worktree and records that no session was left to name", async () => {
  const fixture = createFixture();
  const log = join(fixture.root, "state", "reaped.jsonl");
  const result = await run([
    process.execPath,
    reapScript,
    "--worktree",
    fixture.worktree,
    "--expected-branch",
    "worktree/peer",
    "--expected-head",
    fixture.workerHead,
    "--unowned",
    "--project-root",
    fixture.projectsRoot,
    "--log",
    log,
  ]);

  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toMatchObject({ ok: true, code: "worktree_reaped" });
  expect(existsSync(fixture.worktree)).toBe(false);
  expect(git(fixture.main, "rev-parse", "refs/heads/worktree/peer")).toBe(fixture.workerHead);
  const records = readFileSync(log, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  expect(records.map((record) => record.event)).toEqual(["reap_started", "reaped"]);
  expect(records[1]).toMatchObject({ authorization: "unowned", workspace_id: null, agents: [] });
});

test("the reaper refuses an unowned reap that also claims a lifecycle identity", async () => {
  const fixture = createFixture();
  const log = join(fixture.root, "state", "reaped.jsonl");
  const result = await run([
    process.execPath,
    reapScript,
    "--worktree",
    fixture.worktree,
    "--expected-branch",
    "worktree/peer",
    "--expected-head",
    fixture.workerHead,
    "--unowned",
    "--workspace-id",
    "w4",
    "--project-root",
    fixture.projectsRoot,
    "--log",
    log,
  ]);

  expect(result.exitCode).toBe(64);
  expect(JSON.parse(result.stdout)).toMatchObject({ ok: false, code: "usage" });
  expect(existsSync(fixture.worktree)).toBe(true);
});

test("the reaper preserves a dirty closed worktree", async () => {
  const fixture = createFixture();
  const log = join(fixture.root, "state", "reaped.jsonl");
  writeFileSync(join(fixture.worktree, "uncommitted.txt"), "do not lose\n");
  const result = await run([
    process.execPath,
    reapScript,
    "--worktree",
    fixture.worktree,
    "--expected-branch",
    "worktree/peer",
    "--expected-head",
    fixture.workerHead,
    "--workspace-id",
    "w4",
    "--agent-json",
    JSON.stringify({ harness: "codex", session_id: "session-42", pane_id: "w4:p2" }),
    "--project-root",
    fixture.projectsRoot,
    "--log",
    log,
  ]);

  expect(result.exitCode).toBe(11);
  expect(JSON.parse(result.stdout)).toMatchObject({ ok: false, code: "worktree_not_clean" });
  expect(existsSync(fixture.worktree)).toBe(true);
  expect(existsSync(log)).toBe(false);
});

describe("Git-native worktree discovery", () => {
  test("drops a registration whose checkout no longer exists on disk", () => {
    const fixture = createFixture();
    expect(listLiveWorktrees(fixture.main).map((worktree) => normalizePath(worktree.path))).toContain(
      normalizePath(fixture.worktree),
    );

    // Git keeps the registration until someone prunes it, and reports it as
    // prunable. A supervisor must not offer a checkout that is already gone.
    rmSync(fixture.worktree, { recursive: true, force: true });
    expect(listLiveWorktrees(fixture.main).map((worktree) => normalizePath(worktree.path))).not.toContain(
      normalizePath(fixture.worktree),
    );
  });

  test("finds repositories under a project root without descending into them", () => {
    const fixture = createFixture();
    mkdirSync(join(fixture.main, "node_modules", "package", ".git"), { recursive: true });
    mkdirSync(join(fixture.projectsRoot, "not-a-repo", "nested"), { recursive: true });

    const repositories = findRepositories([fixture.projectsRoot]);
    expect(repositories).toEqual([normalizePath(fixture.main)]);
  });

  test("surveys one repository once however many of its checkouts are under a root", () => {
    const fixture = createFixture();

    // The shape an operator ends up with after giving a repository a dedicated
    // main worktree: their own checkout on a feature branch, a second checkout
    // holding main, both directly under the project root, one repository.
    git(fixture.main, "checkout", "-b", "operator/work");
    const mainHolder = join(fixture.projectsRoot, "project-main");
    git(fixture.main, "worktree", "add", mainHolder, "main");

    // Keyed by path, both checkouts are repositories and every worktree of the
    // repository is surveyed — and counted — twice.
    expect(findRepositories([fixture.projectsRoot])).toEqual([normalizePath(fixture.main)]);

    const surveyed = surveyRepository(fixture.main, [fixture.projectsRoot]);
    expect(surveyed.map((worktree) => worktree.worktree).sort()).toEqual(
      [normalizePath(fixture.main), normalizePath(mainHolder), normalizePath(fixture.worktree)].sort(),
    );
  });

  test("reports worktrees carrying commits main does not, and nothing else", () => {
    const fixture = createFixture();
    const discovered = scanRepository(fixture.main, [fixture.projectsRoot]);
    expect(discovered.map((worktree) => worktree.worktree)).toEqual([normalizePath(fixture.worktree)]);
    expect(discovered[0]).toMatchObject({
      branch: "worktree/peer",
      head: fixture.workerHead,
      commits_ahead: 1,
      clean: true,
      main_worktree: normalizePath(fixture.main),
    });
  });

  test("discovers a worktree with no agent development environment at all", async () => {
    const fixture = createFixture();
    // No socket, so nothing can answer who owns this worktree. Discovery is
    // Git's answer alone and must still report the commit.
    const result = await run([
      process.execPath,
      watchScript,
      "--once",
      "--socket",
      join(fixture.root, "absent.sock"),
      "--project-root",
      fixture.projectsRoot,
    ]);
    const [roster] = emitted(result.stdout);
    expect(roster).toMatchObject({ type: "roster", occasion: "snapshot" });

    const candidate = candidates(result.stdout)[0] ?? {};
    expect(candidate).toMatchObject({
      type: "unowned_candidate",
      reason: "discovered",
      worktree: normalizePath(fixture.worktree),
      head: fixture.workerHead,
    });
  });

  test("reports work an agent committed and quit before the supervisor came online", async () => {
    const fixture = createFixture();

    // A second repository whose peer also finished and left. Nothing is
    // running anywhere: no pane, no session, no lifecycle event will ever
    // mention either of these commits again.
    const second = join(fixture.projectsRoot, "second");
    mkdirSync(second, { recursive: true });
    git(second, "init", "--initial-branch=main");
    git(second, "config", "user.name", "Supervisor Test");
    git(second, "config", "user.email", "supervisor@example.invalid");
    writeFileSync(join(second, "base.txt"), "base\n");
    git(second, "add", "base.txt");
    git(second, "commit", "-m", "base");
    const abandoned = join(fixture.root, "worktrees", "abandoned");
    git(second, "worktree", "add", "-b", "worktree/abandoned", abandoned, "main");
    writeFileSync(join(abandoned, "result.txt"), "finished and quit\n");
    git(abandoned, "add", "result.txt");
    git(abandoned, "commit", "-m", "finished and quit");

    const result = await run([
      process.execPath,
      watchScript,
      "--once",
      "--socket",
      join(fixture.root, "absent.sock"),
      "--project-root",
      fixture.projectsRoot,
    ]);

    const reported = candidates(result.stdout);
    expect(reported.every((candidate) => candidate.type === "unowned_candidate")).toBe(true);
    expect(new Set(reported.map((candidate) => candidate.worktree))).toEqual(
      new Set([normalizePath(fixture.worktree), normalizePath(abandoned)]),
    );
    for (const candidate of reported) {
      expect(candidate).toMatchObject({ reason: "discovered", commits_ahead: 1, clean: true });
    }
  });

  test("reports a worktree created after the watcher is already live", async () => {
    const fixture = createFixture();
    const child = Bun.spawn(
      [
        process.execPath,
        watchScript,
        "--socket",
        join(fixture.root, "absent.sock"),
        "--project-root",
        fixture.projectsRoot,
        "--sweep-interval",
        "0",
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );

    const lines = lineReader(child.stdout);
    try {
      // Every run opens with the roster: what is watched, what has landed,
      // and what is removable, before a single event is reported.
      const roster = JSON.parse(await lines.next());
      expect(roster).toMatchObject({ type: "roster", occasion: "start" });

      // The worktree that already existed is reported from the startup scan.
      const first = JSON.parse(await lines.next());
      expect(first).toMatchObject({ worktree: normalizePath(fixture.worktree) });

      // Now create one Git has never seen, with no ADE involved whatsoever.
      const late = join(fixture.root, "worktrees", "late");
      git(fixture.main, "worktree", "add", "-b", "worktree/late", late, "main");
      writeFileSync(join(late, "late.txt"), "late work\n");
      git(late, "add", "late.txt");
      git(late, "commit", "-m", "late work");

      const second = JSON.parse(await lines.next());
      expect(second).toMatchObject({
        type: "unowned_candidate",
        reason: "discovered",
        worktree: normalizePath(late),
        branch: "worktree/late",
        head: git(late, "rev-parse", "HEAD"),
        commits_ahead: 1,
      });
    } finally {
      lines.release();
      child.kill();
      await child.exited;
    }
  });
});

describe("The roster", () => {
  /** Fast-forward local main onto the peer's commit, as the integrator would. */
  function land(fixture: Fixture): void {
    git(fixture.main, "merge", "--ff-only", "worktree/peer");
  }

  test("places a landed, clean, unowned worktree as removable", async () => {
    const fixture = createFixture();
    land(fixture);

    const roster = await buildRoster([fixture.projectsRoot], null, "test");
    const rows = roster.repositories.flatMap((repository) => repository.worktrees);
    const peer = rows.find((row) => row.worktree === normalizePath(fixture.worktree));

    expect(peer).toMatchObject({
      category: "removable",
      removable: true,
      blockers: [],
      branch: "worktree/peer",
      commits_ahead: 0,
      clean: true,
    });
    expect(roster.counts).toMatchObject({ removable: 1, watching: 0 });

    // The integration target is listed, and is never removable.
    const mainRow = rows.find((row) => row.worktree === normalizePath(fixture.main));
    expect(mainRow).toMatchObject({ category: "main", removable: false });
    expect(roster.repositories[0]).toMatchObject({ main_pushed: false });
  });

  test("holds unmerged work and uncommitted changes back from removal, with the reason", async () => {
    const fixture = createFixture();

    const unmerged = await buildRoster([fixture.projectsRoot], null, "test");
    const carrying = unmerged.repositories
      .flatMap((repository) => repository.worktrees)
      .find((row) => row.worktree === normalizePath(fixture.worktree));
    expect(carrying).toMatchObject({ category: "watching", removable: false });
    expect(carrying?.blockers).toEqual(["1 commit(s) not in main"]);

    // Landed but dirty: nothing left to integrate, still not a directory to delete.
    land(fixture);
    writeFileSync(join(fixture.worktree, "scratch.txt"), "unsaved\n");
    const dirty = await buildRoster([fixture.projectsRoot], null, "test");
    const left = dirty.repositories
      .flatMap((repository) => repository.worktrees)
      .find((row) => row.worktree === normalizePath(fixture.worktree));
    expect(left).toMatchObject({ category: "landed", removable: false });
    expect(left?.blockers).toEqual(["uncommitted changes"]);
  });

  test("names a worktree's owner by its session slug, falling back to the id", () => {
    const worktree = "/tmp/projects/app/worktree-calm-field";
    const named = ownerOf(
      [
        {
          pane_id: "w1:p1",
          cwd: worktree,
          tokens: { conversation: "supervise-peer-worktrees", project: "app  calm-field" },
          agent_session: { agent: "codex", value: "session-1" },
        },
      ],
      worktree,
      null,
    );
    expect(named).toMatchObject({ session_id: "session-1", session_name: "supervise-peer-worktrees" });

    // A session too young to have been named still has an id to address.
    const unnamed = ownerOf(
      [{ pane_id: "w1:p1", cwd: worktree, agent_session: { agent: "codex", value: "session-1" } }],
      worktree,
      null,
    );
    expect(unnamed).toMatchObject({ session_id: "session-1", session_name: null });
  });

  test("quiets a landed worktree its session has not left yet, naming the session", async () => {
    const fixture = createFixture();
    land(fixture);

    const ownership = {
      owner: async (worktree: string) =>
        worktree === normalizePath(fixture.worktree)
          ? {
              harness: "codex",
              session_id: "session-7",
              session_name: "tidy-the-installer",
              pane_id: "pane-7",
            }
          : null,
    };
    const roster = await buildRoster([fixture.projectsRoot], ownership, "test");
    const peer = roster.repositories
      .flatMap((repository) => repository.worktrees)
      .find((row) => row.worktree === normalizePath(fixture.worktree));

    // Nothing to integrate and nothing uncommitted, so the supervisor has no
    // business with it until its agent leaves — but the roster still knows who
    // is there, and says so if asked.
    expect(peer).toMatchObject({
      category: "quiet",
      removable: false,
      owner: { harness: "codex", session_id: "session-7", session_name: "tidy-the-installer" },
    });
    // The human hears the session's own name, not the id that addresses it.
    expect(peer?.blockers).toEqual(["session live (codex tidy-the-installer)"]);
    expect(roster.counts).toMatchObject({ quiet: 1, watching: 0, removable: 0 });

    // And it is not announced: the same worktree emits an event only once the
    // session is gone and it is genuinely a directory to remove.
    const surveyed = surveyRepository(fixture.main, [fixture.projectsRoot]);
    const landed = surveyed.find((row) => row.worktree === normalizePath(fixture.worktree));
    if (!landed) throw new Error("the landed worktree was not surveyed");
    expect(await candidateFromWorktree(landed, ownership)).toBeNull();
    expect(await candidateFromWorktree(landed, { owner: async () => null })).toMatchObject({
      type: "removable_worktree",
      removable: true,
    });
  });

  test("keeps a worktree where no work has ever been done out of the picture", async () => {
    const fixture = createFixture();
    const fresh = join(fixture.root, "worktrees", "fresh");
    git(fixture.main, "worktree", "add", "-b", "worktree/fresh", fresh, "main");

    const surveyed = surveyRepository(fixture.main, [fixture.projectsRoot]);
    const untouched = surveyed.find((row) => row.worktree === normalizePath(fresh));
    expect(untouched).toMatchObject({ state: "landed", clean: true, worked: false });

    // No commit was ever made here, so it is not the supervisor's business at
    // all: the stream says nothing about it and the roster does not count it,
    // not even as quiet.
    const roster = await buildRoster([fixture.projectsRoot], null, "test");
    const rows = roster.repositories.flatMap((repository) => repository.worktrees);
    expect(rows.find((entry) => entry.worktree === normalizePath(fresh))).toBeUndefined();
    expect(roster.counts.quiet).toBe(0);
    if (!untouched) throw new Error("the untouched worktree was not surveyed");
    expect(await candidateFromWorktree(untouched, null)).toBeNull();

    // The first commit made there is work, and it is watched like any other.
    writeFileSync(join(fresh, "first.txt"), "first\n");
    git(fresh, "add", "first.txt");
    git(fresh, "commit", "-m", "first work");
    const working = surveyRepository(fixture.main, [fixture.projectsRoot]).find(
      (entry) => entry.worktree === normalizePath(fresh),
    );
    expect(working).toMatchObject({ state: "unmerged", worked: true });
    const after = await buildRoster([fixture.projectsRoot], null, "test");
    expect(
      after.repositories
        .flatMap((repository) => repository.worktrees)
        .find((entry) => entry.worktree === normalizePath(fresh)),
    ).toMatchObject({ category: "watching" });
  });

  test("keeps a repository whose main is not checked out anywhere, with the reason", async () => {
    const fixture = createFixture();

    // An operator commits their work and switches their one checkout to a
    // feature branch. Nothing was deleted and nothing is finished; there is
    // simply nowhere to integrate into any more.
    git(fixture.main, "checkout", "-b", "operator/work");

    const roster = await buildRoster([fixture.projectsRoot], null, "test");
    const repository = roster.repositories.find(
      (entry) => entry.repository === normalizePath(fixture.main),
    );

    // The repository is on the roster, saying what is wrong with it, and its
    // checkouts are all still named. Dropping them silently is what makes a
    // supervised repository and an unsupervised one read the same.
    expect(repository).toMatchObject({ main_worktree: null, main_head: null, main_pushed: null });
    expect(repository?.blockers).toEqual(["no local main checked out"]);
    expect(repository?.worktrees.map((row) => row.worktree).sort()).toEqual(
      [normalizePath(fixture.main), normalizePath(fixture.worktree)].sort(),
    );
    for (const row of repository?.worktrees ?? []) {
      expect(row).toMatchObject({ category: "unsupervised", removable: false, commits_ahead: null });
      expect(row.blockers).toEqual(["no local main checked out"]);
    }
    expect(roster.counts).toMatchObject({ unsupervised: 2, removable: 0, quiet: 0 });
  });

  test("counts one repository once however many of its checkouts are under a root", async () => {
    const fixture = createFixture();
    git(fixture.main, "checkout", "-b", "operator/work");
    git(fixture.main, "worktree", "add", join(fixture.projectsRoot, "project-main"), "main");

    const roster = await buildRoster([fixture.projectsRoot], null, "test");
    expect(roster.repositories).toHaveLength(1);

    // Every worktree of the repository appears exactly once, whichever of its
    // checkouts the survey entered through.
    const rows = roster.repositories.flatMap((repository) => repository.worktrees);
    expect(new Set(rows.map((row) => row.worktree)).size).toBe(rows.length);
    expect(roster.counts).toMatchObject({ watching: 1 });
  });

  test("never offers a repository's primary checkout for removal", async () => {
    const fixture = createFixture();

    // The primary checkout does the work, a dedicated worktree holds main, and
    // the work lands. Clean, nobody in it, nothing left to integrate — every
    // condition for removal except the one that matters.
    git(fixture.main, "checkout", "-b", "operator/work");
    writeFileSync(join(fixture.main, "operator.txt"), "operator work\n");
    git(fixture.main, "add", "operator.txt");
    git(fixture.main, "commit", "-m", "operator work");
    const operatorHead = git(fixture.main, "rev-parse", "HEAD");
    const mainHolder = join(fixture.projectsRoot, "project-main");
    git(fixture.main, "worktree", "add", mainHolder, "main");
    git(mainHolder, "merge", "--ff-only", "operator/work");

    const roster = await buildRoster([fixture.projectsRoot], null, "test");
    const operator = roster.repositories
      .flatMap((repository) => repository.worktrees)
      .find((row) => row.worktree === normalizePath(fixture.main));
    expect(operator).toMatchObject({ category: "landed", removable: false, clean: true });
    expect(operator?.blockers).toEqual(["the repository's primary checkout"]);

    // And no event ever says otherwise.
    const surveyed = surveyRepository(fixture.main, [fixture.projectsRoot]);
    const landed = surveyed.find((row) => row.worktree === normalizePath(fixture.main));
    if (!landed) throw new Error("the primary checkout was not surveyed");
    expect(await candidateFromWorktree(landed, null)).toMatchObject({
      type: "removable_worktree",
      removable: false,
      blockers: ["the repository's primary checkout"],
    });

    // The reaper refuses it on its own account, so a stale or hand-passed
    // event cannot delete an operator's working directory either.
    const result = await run([
      process.execPath,
      reapScript,
      "--worktree",
      fixture.main,
      "--expected-branch",
      "operator/work",
      "--expected-head",
      operatorHead,
      "--workspace-id",
      "workspace-1",
      "--agent-json",
      JSON.stringify({ harness: "codex", session_id: "session-1", pane_id: "w1:p1" }),
      "--project-root",
      fixture.projectsRoot,
      "--log",
      join(fixture.root, "reaped.jsonl"),
    ]);
    expect(result.exitCode).toBe(12);
    expect(JSON.parse(result.stdout)).toMatchObject({ ok: false, code: "primary_worktree_refused" });
    expect(existsSync(join(fixture.main, "operator.txt"))).toBe(true);
    expect(existsSync(join(fixture.root, "reaped.jsonl"))).toBe(false);
  });

  test("status.ts prints the same roster on demand", async () => {
    const fixture = createFixture();
    land(fixture);

    const result = await run([
      process.execPath,
      statusScript,
      "--socket",
      join(fixture.root, "absent.sock"),
      "--project-root",
      fixture.projectsRoot,
      "--occasion",
      "stop",
    ]);
    const roster = JSON.parse(result.stdout.trim());
    expect(roster).toMatchObject({
      type: "roster",
      occasion: "stop",
      // No ADE answered, so no session is knowable and the roster says so
      // rather than letting silence read as "nobody is working here".
      ownership_available: false,
      counts: { removable: 1 },
    });
  });

  test("offers an ignored worktree again on the next scan", async () => {
    const fixture = createFixture();
    land(fixture);

    const offered: string[] = [];
    let reported = false;
    const discovery = new WorktreeDiscovery({
      projectRoots: [fixture.projectsRoot],
      sweepIntervalSeconds: 0,
      onWorktree: (worktree) => {
        if (worktree.worktree === normalizePath(fixture.worktree)) offered.push(worktree.head);
        return reported;
      },
    });

    try {
      discovery.start();
      discovery.drainNow();
      await Promise.resolve();
      expect(offered).toEqual([fixture.workerHead]);

      // Nothing changed in Git — and that is the point. A worktree passed over
      // because of who was sitting in it must be reconsidered when nobody is,
      // and no ref moves when an agent quits.
      reported = true;
      discovery.sweep();
      discovery.drainNow();
      await Promise.resolve();
      expect(offered).toEqual([fixture.workerHead, fixture.workerHead]);

      // Once it has been reported, the same situation is not offered again.
      discovery.sweep();
      discovery.drainNow();
      await Promise.resolve();
      expect(offered).toHaveLength(2);
    } finally {
      discovery.stop();
    }
  });

  test("the survey keeps landed worktrees the candidate scan drops", () => {
    const fixture = createFixture();
    land(fixture);

    expect(scanRepository(fixture.main, [fixture.projectsRoot])).toEqual([]);
    const surveyed = surveyRepository(fixture.main, [fixture.projectsRoot]);
    expect(
      surveyed.map((worktree) => [worktree.worktree, worktree.state]),
    ).toEqual(
      expect.arrayContaining([
        [normalizePath(fixture.main), "main"],
        [normalizePath(fixture.worktree), "landed"],
      ]),
    );
  });

  test("the watcher announces a worktree as removable once its work is in main", async () => {
    const fixture = createFixture();
    const child = Bun.spawn(
      [
        process.execPath,
        watchScript,
        "--socket",
        join(fixture.root, "absent.sock"),
        "--project-root",
        fixture.projectsRoot,
        "--sweep-interval",
        "0",
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );

    const lines = lineReader(child.stdout);
    try {
      expect(JSON.parse(await lines.next())).toMatchObject({ type: "roster", occasion: "start" });
      expect(JSON.parse(await lines.next())).toMatchObject({
        type: "unowned_candidate",
        worktree: normalizePath(fixture.worktree),
      });

      // Local main moves onto that exact commit, as the integrator does. The
      // worktree's HEAD has not changed at all — only its situation has.
      land(fixture);

      expect(JSON.parse(await lines.next())).toMatchObject({
        type: "removable_worktree",
        worktree: normalizePath(fixture.worktree),
        branch: "worktree/peer",
        head: fixture.workerHead,
        removable: true,
        blockers: [],
        owner: null,
      });
    } finally {
      lines.release();
      child.kill();
      await child.exited;
    }
  });
});
