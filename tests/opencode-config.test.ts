import { afterEach, expect, test } from "bun:test";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const script = join(import.meta.dir, "../scripts/opencode-config");
const temporary: string[] = [];

afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const home = mkdtempSync(join(realpathSync(tmpdir()), "agentstart-opencode-config-"));
  temporary.push(home);
  const target = join(home, ".config", "opencode", "cli.json");
  const run = (command = "--install") =>
    Bun.spawnSync([script, command], {
      env: { HOME: home, XDG_CONFIG_HOME: join(home, ".config"), PATH: process.env.PATH ?? "" },
      stdout: "pipe",
      stderr: "pipe",
    });
  return { home, target, run };
}

test("creates the OpenCode 2 CLI bindings and leaves an identical file untouched", () => {
  const f = fixture();
  expect(f.run().exitCode).toBe(0);
  const content = readFileSync(f.target, "utf8");
  expect(JSON.parse(content)).toEqual({
    $schema: "https://opencode.ai/v2/cli.json",
    keybinds: { "session.tab.next": "alt+2", "session.tab.previous": "alt+1" },
  });
  const before = lstatSync(f.target);
  expect(f.run().exitCode).toBe(0);
  expect(lstatSync(f.target).ino).toBe(before.ino);
  expect(lstatSync(f.target).mode & 0o777).toBe(0o600);
});

test("merges bindings into native settings without dropping other keys", () => {
  const f = fixture();
  mkdirSync(join(f.home, ".config", "opencode"), { recursive: true });
  writeFileSync(f.target, JSON.stringify({ tabs: { mode: "on" }, keybinds: { "app.exit": "ctrl+c", "session.tab.next": "ctrl+tab" } }), { mode: 0o640 });
  expect(f.run().exitCode).toBe(0);
  expect(JSON.parse(readFileSync(f.target, "utf8"))).toEqual({
    tabs: { mode: "on" },
    keybinds: { "app.exit": "ctrl+c", "session.tab.next": "alt+2", "session.tab.previous": "alt+1" },
  });
  expect(lstatSync(f.target).mode & 0o777).toBe(0o640);
});

test("refuses redirected and malformed native settings rather than replacing them", () => {
  const linked = fixture();
  mkdirSync(join(linked.home, ".config", "opencode"), { recursive: true });
  const foreign = join(linked.home, "foreign.json");
  writeFileSync(foreign, "{}\n");
  symlinkSync(foreign, linked.target);
  expect(linked.run().exitCode).not.toBe(0);
  expect(readFileSync(foreign, "utf8")).toBe("{}\n");

  const malformed = fixture();
  mkdirSync(join(malformed.home, ".config", "opencode"), { recursive: true });
  writeFileSync(malformed.target, "{ not json }");
  expect(malformed.run().exitCode).not.toBe(0);
  expect(readFileSync(malformed.target, "utf8")).toBe("{ not json }");
});

test("check advertises convergence without writing settings", () => {
  const f = fixture();
  expect(f.run("--check").stdout.toString()).toContain("Alt+1/Alt+2");
  expect(existsSync(f.target)).toBe(false);
});
