import { afterEach, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const helper = join(import.meta.dir, "../scripts/install-pi");
const temporary: string[] = [];

afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const base = mkdtempSync(join(tmpdir(), "agentstart-pi-"));
  temporary.push(base);
  const home = join(base, "home with spaces");
  const fixtureBin = join(base, "fixture-bin");
  const globalPrefix = join(base, "global prefix");
  const log = join(base, "npm-calls");
  const state = join(base, "installed");
  const fakePi = join(fixtureBin, "fixture-pi");
  mkdirSync(home);
  mkdirSync(fixtureBin);
  mkdirSync(join(globalPrefix, "bin"), { recursive: true });
  mkdirSync(join(globalPrefix, "lib", "node_modules"), { recursive: true });

  const node = join(fixtureBin, "node");
  writeFileSync(
    node,
    `#!/bin/bash
case "\${1:-}" in
  --version) printf '%s\\n' "\${FIXTURE_NODE_VERSION:-v22.19.0}" ;;
  -e) printf '%s' "\${FIXTURE_PACKAGE_VERSION:-0.85.1}" ;;
  *) exit 64 ;;
esac
`,
    { mode: 0o755 },
  );
  writeFileSync(fakePi, "#!/bin/bash\nprintf '%s\\n' \"\${FIXTURE_PI_VERSION:-0.85.1}\"\n", { mode: 0o755 });

  const npm = join(fixtureBin, "npm");
  writeFileSync(
    npm,
    `#!/bin/bash
printf 'npm' >> "$FIXTURE_LOG"
printf ' <%s>' "$@" >> "$FIXTURE_LOG"
printf '\\n' >> "$FIXTURE_LOG"
case "\${1:-}" in
  prefix)
    printf '%s\\n' "$FIXTURE_GLOBAL_PREFIX"
    ;;
  install)
    [ "\${FIXTURE_INSTALL_STATUS:-0}" -eq 0 ] || exit "$FIXTURE_INSTALL_STATUS"
    mkdir -p "$FIXTURE_INSTALL_PREFIX/bin" "$FIXTURE_INSTALL_PREFIX/lib/node_modules/@earendil-works/pi-coding-agent"
    : > "$FIXTURE_STATE"
    : > "$FIXTURE_INSTALL_PREFIX/lib/node_modules/@earendil-works/pi-coding-agent/package.json"
    if [ "\${FIXTURE_SKIP_PI:-0}" -ne 1 ]; then
      ln -sfn "$FIXTURE_PI_BIN" "$FIXTURE_INSTALL_PREFIX/bin/pi"
    fi
    ;;
  list)
    [ -e "$FIXTURE_STATE" ] || exit 1
    exit "\${FIXTURE_LIST_STATUS:-0}"
    ;;
  *) exit 64 ;;
esac
`,
    { mode: 0o755 },
  );

  function run(args: string[], extraEnv: Record<string, string> = {}) {
    const selectedPrefix = extraEnv.FIXTURE_INSTALL_PREFIX ?? globalPrefix;
    return Bun.spawnSync(["/bin/bash", helper, ...args], {
      cwd: base,
      env: {
        HOME: home,
        PATH: `${fixtureBin}:${join(home, ".local", "bin")}:${join(globalPrefix, "bin")}:/usr/bin:/bin`,
        AGENTSTART_PI_NODE_BIN: node,
        AGENTSTART_PI_NPM_BIN: npm,
        FIXTURE_GLOBAL_PREFIX: globalPrefix,
        FIXTURE_INSTALL_PREFIX: selectedPrefix,
        FIXTURE_LOG: log,
        FIXTURE_STATE: state,
        FIXTURE_PI_BIN: fakePi,
        ...extraEnv,
      },
      stdout: "pipe",
      stderr: "pipe",
    });
  }

  return { globalPrefix, home, log, run };
}

test("check mode names the explicit npm action without running a dependency", () => {
  const f = fixture();
  const result = f.run(["--check"]);
  expect(result.exitCode, result.stderr.toString()).toBe(0);
  expect(result.stdout.toString()).toContain(
    "npm install -g --ignore-scripts --min-release-age=0 [--prefix ~/.local when needed] --no-fund --no-audit --loglevel=error --progress=false @earendil-works/pi-coding-agent",
  );
  expect(existsSync(f.log)).toBe(false);
});

test("installs or updates Pi with the exact explicit upstream npm action", () => {
  const f = fixture();
  const result = f.run(["--install"]);
  expect(result.exitCode, result.stderr.toString()).toBe(0);
  expect(readFileSync(f.log, "utf8")).toBe(
    "npm <prefix> <-g>\n" +
      "npm <install> <-g> <--ignore-scripts> <--min-release-age=0> <--no-fund> <--no-audit> <--loglevel=error> <--progress=false> <@earendil-works/pi-coding-agent>\n" +
      "npm <list> <-g> <--depth=0> <@earendil-works/pi-coding-agent>\n",
  );
  expect(result.stdout.toString()).not.toContain("Choose an action");
  expect(result.stdout.toString()).not.toContain("default");
});

test("uses the user-local prefix explicitly when npm's global prefix is not writable", () => {
  const f = fixture();
  chmodSync(join(f.globalPrefix, "bin"), 0o555);
  chmodSync(join(f.globalPrefix, "lib", "node_modules"), 0o555);
  const localPrefix = join(f.home, ".local");
  const result = f.run(["--install"], { FIXTURE_INSTALL_PREFIX: localPrefix });
  expect(result.exitCode, result.stderr.toString()).toBe(0);
  expect(readFileSync(f.log, "utf8")).toContain(
    `npm <install> <-g> <--ignore-scripts> <--min-release-age=0> <--prefix> <${localPrefix}> <--no-fund> <--no-audit> <--loglevel=error> <--progress=false> <@earendil-works/pi-coding-agent>`,
  );
});

test("propagates npm installation failure without entering a prompt path", () => {
  const f = fixture();
  const result = f.run(["--install"], { FIXTURE_INSTALL_STATUS: "17" });
  expect(result.exitCode).toBe(17);
  expect(result.stdout.toString() + result.stderr.toString()).not.toContain("Choose an action");
});

test("fails when npm reports success without installing the Pi executable", () => {
  const f = fixture();
  const result = f.run(["--install"], { FIXTURE_SKIP_PI: "1" });
  expect(result.exitCode).toBe(1);
  expect(result.stderr.toString()).toContain("npm did not install an executable Pi command");
});

test("rejects an unsupported Node.js version before invoking npm", () => {
  const f = fixture();
  const result = f.run(["--install"], { FIXTURE_NODE_VERSION: "v22.18.9" });
  expect(result.exitCode).toBe(1);
  expect(result.stderr.toString()).toContain("Pi requires Node.js 22.19.0 or newer");
  expect(existsSync(f.log)).toBe(false);
});

for (const args of [[], ["--install", "extra"], ["--wat"]]) {
  test(`rejects unsupported arguments: ${JSON.stringify(args)}`, () => {
    const f = fixture();
    const result = f.run(args);
    expect(result.exitCode).toBe(64);
    expect(existsSync(f.log)).toBe(false);
  });
}

test("contains no vendor prompt/default mechanism or fleet integration", () => {
  const source = readFileSync(helper, "utf8");
  for (const retired of ["pi.dev/install.sh", "/dev/tty", "Choose an action", "integration install", "/.pi"]) {
    expect(source).not.toContain(retired);
  }
});
