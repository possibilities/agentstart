import { afterEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const helper = join(import.meta.dir, "../scripts/install-opencode2");
const temporary: string[] = [];

afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const base = mkdtempSync(join(tmpdir(), "agentstart-opencode2-"));
  temporary.push(base);
  const home = join(base, "home");
  const binDir = join(home, ".local", "bin");
  const prefix = join(home, ".local", "libexec", "agentstart", "opencode2");
  const tools = join(base, "tools");
  const log = join(base, "npm-log");
  mkdirSync(binDir, { recursive: true });
  mkdirSync(tools);
  writeFileSync(join(tools, "opencode"), "#!/bin/bash\nprintf '1.18.32\\n'\n", { mode: 0o755 });
  writeFileSync(
    join(tools, "npm"),
    `#!/bin/bash
printf 'npm' >> "$FIXTURE_LOG"
printf ' <%s>' "$@" >> "$FIXTURE_LOG"
printf '\n' >> "$FIXTURE_LOG"
case "\${1:-}" in
  install)
    [ "\${FIXTURE_INSTALL_STATUS:-0}" -eq 0 ] || exit "$FIXTURE_INSTALL_STATUS"
    mkdir -p "$FIXTURE_PREFIX/bin" "$FIXTURE_PREFIX/lib/node_modules/@opencode/cli"
    printf '{"name":"@opencode/cli","version":"2.0.16"}\n' > "$FIXTURE_PREFIX/lib/node_modules/@opencode/cli/package.json"
    printf '#!/bin/bash\nprintf "opencode v%%s\\n" "\${FIXTURE_VERSION:-2.0.16}"\n' > "$FIXTURE_PREFIX/bin/opencode2"
    chmod +x "$FIXTURE_PREFIX/bin/opencode2"
    ;;
  list)
    [ -f "$FIXTURE_PREFIX/lib/node_modules/@opencode/cli/package.json" ]
    ;;
  *) exit 64 ;;
esac
`,
    { mode: 0o755 },
  );
  function run(args: string[], extraEnv: Record<string, string> = {}) {
    return Bun.spawnSync(["/bin/bash", helper, ...args], {
      cwd: base,
      env: {
        HOME: home,
        PATH: `${tools}:${binDir}:/usr/bin:/bin`,
        AGENTSTART_OPENCODE2_PREFIX: prefix,
        AGENTSTART_OPENCODE2_BIN_DIR: binDir,
        FIXTURE_PREFIX: prefix,
        FIXTURE_LOG: log,
        ...extraEnv,
      },
      stdout: "pipe",
      stderr: "pipe",
    });
  }
  return { base, binDir, home, log, prefix, run };
}

test("check names the pinned private install without invoking npm", () => {
  const f = fixture();
  const result = f.run(["--check"]);
  expect(result.exitCode).toBe(0);
  expect(result.stdout.toString()).toContain("@opencode/cli@2.0.16");
  expect(existsSync(f.log)).toBe(false);
});

test("installs only opencode2 and converges the same owned link", () => {
  const f = fixture();
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = f.run(["--install"]);
    expect(result.exitCode, result.stderr.toString()).toBe(0);
  }
  expect(readFileSync(f.log, "utf8")).toContain(
    `npm <install> <--global> <--prefix> <${f.prefix}> <--no-fund> <--no-audit> <--loglevel=error> <--progress=false> <@opencode/cli@2.0.16>`,
  );
  expect(Bun.spawnSync([join(f.binDir, "opencode2"), "--version"]).stdout.toString()).toBe(
    "opencode v2.0.16\n",
  );
  expect(existsSync(join(f.binDir, "opencode"))).toBe(false);
});

test("refuses an independent command or private prefix", () => {
  const f = fixture();
  symlinkSync(join(f.base, "foreign"), join(f.binDir, "opencode2"));
  expect(f.run(["--install"]).stderr.toString()).toContain("independent command");
  expect(existsSync(f.log)).toBe(false);

  const other = fixture();
  mkdirSync(other.prefix, { recursive: true });
  expect(other.run(["--install"]).stderr.toString()).toContain("independent prefix");
  expect(existsSync(other.log)).toBe(false);
});

test("does not publish a missing or wrong-version install", () => {
  const f = fixture();
  expect(f.run(["--install"], { FIXTURE_INSTALL_STATUS: "17" }).exitCode).toBe(17);
  expect(existsSync(join(f.binDir, "opencode2"))).toBe(false);
  const wrong = f.run(["--install"], { FIXTURE_VERSION: "2.0.15" });
  expect(wrong.stderr.toString()).toContain("expected OpenCode 2.0.16");
  expect(existsSync(join(f.binDir, "opencode2"))).toBe(false);
});
