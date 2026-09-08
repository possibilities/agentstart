import { afterEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const helper = join(import.meta.dir, "../scripts/install-agentvoice-android");
const temporary: string[] = [];

afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const base = mkdtempSync(join(tmpdir(), "agentstart-agentvoice-android-"));
  temporary.push(base);
  const codeRoot = join(base, "fleet with spaces");
  const home = join(base, "home");
  const checkout = join(codeRoot, "agentvoice");
  const log = join(base, "calls");
  mkdirSync(join(checkout, "scripts"), { recursive: true });
  mkdirSync(home);
  symlinkSync(codeRoot, join(home, "code"), "dir");

  function installAndroid(exitCode = 0) {
    writeFileSync(
      join(checkout, "scripts/install-android"),
      `#!/bin/bash\nprintf 'argc=%s\\n' "$#" >> "$FIXTURE_LOG"\nprintf '<%s>\\n' "$@" >> "$FIXTURE_LOG"\nexit ${exitCode}\n`,
      { mode: 0o755 },
    );
  }

  function run(args: string[], extraEnv: Record<string, string> = {}) {
    return Bun.spawnSync(["/bin/bash", helper, ...args], {
      cwd: base,
      env: { HOME: home, AGENTSTART_CODE_ROOT: codeRoot, FIXTURE_LOG: log, ...extraEnv },
      stdout: "pipe",
      stderr: "pipe",
    });
  }

  return { base, checkout, log, installAndroid, run };
}

test("delegates exactly once to the checkout installer with the default host", () => {
  const f = fixture();
  f.installAndroid();
  const result = f.run(["--install"], { AGENTSTART_CODE_ROOT: "" });
  expect(result.exitCode, result.stderr.toString()).toBe(0);
  expect(readFileSync(f.log, "utf8")).toBe("argc=3\n<--install>\n<--host>\n<smolbird>\n");
});

test("honors the relocated fleet and host override without splitting the host", () => {
  const f = fixture();
  f.installAndroid();
  const result = f.run(["--install"], { AGENTSTART_AGENTVOICE_ANDROID_HOST: "phone with spaces" });
  expect(result.exitCode, result.stderr.toString()).toBe(0);
  expect(readFileSync(f.log, "utf8")).toBe("argc=3\n<--install>\n<--host>\n<phone with spaces>\n");
});

for (const args of [[], ["--check"], ["--install", "extra"]]) {
  test(`rejects unsupported arguments: ${JSON.stringify(args)}`, () => {
    const f = fixture();
    f.installAndroid();
    const result = f.run(args);
    expect(result.exitCode).toBe(64);
    expect(result.stderr.toString()).toContain("Usage: install-agentvoice-android --install");
    expect(existsSync(f.log)).toBe(false);
  });
}

for (const kind of ["missing-checkout", "broken-checkout-link", "missing-installer", "non-executable"] as const) {
  test(`rejects a missing or broken checkout contract: ${kind}`, () => {
    const f = fixture();
    if (kind === "missing-checkout") rmSync(f.checkout, { recursive: true });
    if (kind === "broken-checkout-link") {
      rmSync(f.checkout, { recursive: true });
      symlinkSync(join(f.base, "absent"), f.checkout);
    }
    if (kind === "non-executable")
      writeFileSync(join(f.checkout, "scripts/install-android"), "#!/bin/bash\nexit 0\n", { mode: 0o644 });
    const result = f.run(["--install"]);
    expect(result.exitCode).toBe(1);
    expect(existsSync(f.log)).toBe(false);
  });
}

test("propagates the checkout installer's failure", () => {
  const f = fixture();
  f.installAndroid(17);
  const result = f.run(["--install"]);
  expect(result.exitCode).toBe(17);
  expect(readFileSync(f.log, "utf8")).toBe("argc=3\n<--install>\n<--host>\n<smolbird>\n");
});

test("the optional deployment is absent from every default convergence path", () => {
  for (const script of ["install.sh", "sync-skills", "install-agent-clis"]) {
    const source = readFileSync(join(import.meta.dir, `../scripts/${script}`), "utf8");
    expect(source).not.toContain("install-agentvoice-android");
    expect(source).not.toContain("install-android");
  }
});
