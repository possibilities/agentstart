import { afterEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const temporary: string[] = [];
afterEach(() => {
  for (const path of temporary.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const base = mkdtempSync(join(tmpdir(), "agentstart-cli-test-"));
  temporary.push(base);
  const root = join(base, "fleet with spaces");
  const bin = join(base, "commands");
  mkdirSync(root);
  mkdirSync(bin);
  // The dispatcher has no platform-specific work beyond these guards.
  writeFileSync(join(bin, "uname"), "#!/bin/bash\nprintf 'Darwin\\n'\n", { mode: 0o755 });
  writeFileSync(join(bin, "id"), "#!/bin/bash\nprintf '501\\n'\n", { mode: 0o755 });
  function installer(name: string, code = 0) {
    const dir = join(root, name, "scripts");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "install.sh"), `#!/bin/bash\nprintf '%s:%s\\n' '${name}' "$*" >> "$FIXTURE_LOG"\nexit ${code}\n`, { mode: 0o755 });
  }
  function run(args: string[] = []) {
    return Bun.spawnSync(["/bin/bash", join(import.meta.dir, "../scripts/install-agent-clis"), ...args], {
      cwd: base,
      env: { PATH: bin, AGENTSTART_CODE_ROOT: root, FIXTURE_LOG: join(base, "calls") },
      stdout: "pipe", stderr: "pipe",
    });
  }
  return { base, root, installer, run };
}

test("missing checkouts skip and AgentVoice delegates once with only --install; rerunnable", () => {
  const f = fixture();
  f.installer("agentvoice");
  for (let count = 0; count < 2; count++) {
    const result = f.run();
    expect(result.exitCode, result.stderr.toString()).toBe(0);
    expect(result.stdout.toString()).toContain("no checkout");
  }
  expect(readFileSync(join(f.base, "calls"), "utf8")).toBe("agentvoice:--install\nagentvoice:--install\n");
});

for (const kind of ["missing-installer", "non-executable", "broken-checkout-link", "failed-installer"]) {
  test(`present but broken AgentVoice is not a skip: ${kind}`, () => {
    const f = fixture();
    if (kind === "missing-installer") mkdirSync(join(f.root, "agentvoice"));
    if (kind === "non-executable") {
      mkdirSync(join(f.root, "agentvoice/scripts"), { recursive: true });
      writeFileSync(join(f.root, "agentvoice/scripts/install.sh"), "#!/bin/bash\nexit 0\n", { mode: 0o644 });
    }
    if (kind === "broken-checkout-link") symlinkSync(join(f.base, "absent"), join(f.root, "agentvoice"));
    if (kind === "failed-installer") f.installer("agentvoice", 17);
    const result = f.run();
    expect(result.exitCode).toBe(kind === "failed-installer" ? 17 : 1);
    if (kind !== "failed-installer") expect(existsSync(join(f.base, "calls"))).toBe(false);
  });
}

test("argument errors and an earlier failed contract stop before AgentVoice", () => {
  const f = fixture();
  f.installer("agentwiki", 19);
  f.installer("agentvoice");
  expect(f.run(["--install"]).exitCode).toBe(64);
  expect(existsSync(join(f.base, "calls"))).toBe(false);
  expect(f.run().exitCode).toBe(19);
  expect(readFileSync(join(f.base, "calls"), "utf8")).toBe("agentwiki:--install\n");
});
