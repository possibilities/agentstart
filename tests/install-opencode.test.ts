import { afterEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const helper = join(import.meta.dir, "../scripts/install-opencode");
const temporary: string[] = [];

afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const base = mkdtempSync(join(tmpdir(), "agentstart-opencode-"));
  temporary.push(base);
  const home = join(base, "home");
  const binDir = join(home, ".local", "bin");
  const legacyBin = join(home, ".opencode", "bin");
  const prefix = join(home, ".local", "libexec", "agentstart", "opencode2");
  const tools = join(base, "tools");
  const log = join(base, "npm-log");
  mkdirSync(binDir, { recursive: true });
  mkdirSync(legacyBin, { recursive: true });
  mkdirSync(tools);
  writeFileSync(join(legacyBin, "opencode"), "#!/bin/bash\nprintf '1.18.32\\n'\n", { mode: 0o755 });
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
    printf '#!/bin/bash\nprintf "opencode v%%s\\n" "\${FIXTURE_VERSION:-2.0.16}"\n' > "$FIXTURE_PREFIX/bin/opencode"
    chmod +x "$FIXTURE_PREFIX/bin/opencode"
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
        PATH: `${tools}:${binDir}:${legacyBin}:/usr/bin:/bin`,
        AGENTSTART_OPENCODE2_PREFIX: prefix,
        AGENTSTART_OPENCODE_BIN_DIR: binDir,
        FIXTURE_PREFIX: prefix,
        FIXTURE_LOG: log,
        ...extraEnv,
      },
      stdout: "pipe",
      stderr: "pipe",
    });
  }
  return { base, binDir, legacyBin, log, prefix, run };
}

test("check names the pinned private install and default command without invoking npm", () => {
  const f = fixture();
  const result = f.run(["--check"]);
  expect(result.exitCode).toBe(0);
  expect(result.stdout.toString()).toContain("@opencode/cli@2.0.16");
  expect(result.stdout.toString()).toContain("~/.local/bin/opencode");
  expect(existsSync(f.log)).toBe(false);
});

test("cuts over opencode and retires only the owned opencode2 link", () => {
  const f = fixture();
  symlinkSync(join(f.prefix, "bin", "opencode2"), join(f.binDir, "opencode2"));
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = f.run(["--install"]);
    expect(result.exitCode, result.stderr.toString()).toBe(0);
  }
  expect(readFileSync(f.log, "utf8")).toContain(
    `npm <install> <--global> <--prefix> <${f.prefix}> <--no-fund> <--no-audit> <--loglevel=error> <--progress=false> <@opencode/cli@2.0.16>`,
  );
  expect(readFileSync(f.log, "utf8").match(/npm <install>/g)?.length).toBe(1);
  expect(Bun.spawnSync([join(f.binDir, "opencode"), "--version"]).stdout.toString()).toBe(
    "opencode v2.0.16\n",
  );
  expect(existsSync(join(f.binDir, "opencode2"))).toBe(false);
  expect(readFileSync(join(f.legacyBin, "opencode"), "utf8")).toContain("1.18.32");
});

test("refuses independent commands and private prefixes", () => {
  const f = fixture();
  symlinkSync(join(f.base, "foreign"), join(f.binDir, "opencode"));
  expect(f.run(["--install"]).stderr.toString()).toContain("independent command");
  expect(existsSync(f.log)).toBe(false);

  const retired = fixture();
  symlinkSync(join(retired.base, "foreign"), join(retired.binDir, "opencode2"));
  expect(retired.run(["--install"]).stderr.toString()).toContain("independent command");
  expect(existsSync(retired.log)).toBe(false);

  const other = fixture();
  mkdirSync(other.prefix, { recursive: true });
  expect(other.run(["--install"]).stderr.toString()).toContain("independent prefix");
  expect(existsSync(other.log)).toBe(false);
});

test("does not publish a missing or wrong-version install", () => {
  const f = fixture();
  expect(f.run(["--install"], { FIXTURE_INSTALL_STATUS: "17" }).exitCode).toBe(17);
  expect(existsSync(join(f.binDir, "opencode"))).toBe(false);
  const wrong = f.run(["--install"], { FIXTURE_VERSION: "2.0.15" });
  expect(wrong.stderr.toString()).toContain("expected OpenCode 2.0.16");
  expect(existsSync(join(f.binDir, "opencode"))).toBe(false);
});
