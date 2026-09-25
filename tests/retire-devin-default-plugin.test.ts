import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { retireDefaultPlugin } from "../scripts/retire-devin-default-plugin.ts";

let home: string;
beforeEach(() => {
  home = mkdtempSync(join(tmpdir(), "agentstart-retire-devin-"));
  mkdirSync(join(home, ".cache/agentroles/devin/default"), { recursive: true });
  mkdirSync(join(home, ".local/share/agentstart/resources/roles/default"), { recursive: true });
});
afterEach(() => rmSync(home, { recursive: true, force: true }));

test("retires only the exact local AgentRoles default after live sessions end", async () => {
  let installed = true;
  const calls: string[] = [];
  const run = async (args: string[]) => {
    calls.push(args.join(" "));
    if (args[1] === "list") return { code: 0, stdout: installed ? "Installed plugins\n\n  • default v0.0.0\n" : "Installed plugins\n\n  (none)\n", stderr: "" };
    if (args[1] === "info") return { code: 0, stdout: `Plugin: default\n  source: ${realpathSync(join(home, ".cache/agentroles/devin/default"))}\n  description: agentroles role default (${join(home, ".local/share/agentstart/resources/roles/default")})\n`, stderr: "" };
    if (args[1] === "remove") { installed = false; return { code: 0, stdout: "removed", stderr: "" }; }
    throw new Error("unexpected native command");
  };
  expect(await retireDefaultPlugin("/native/devin", home, run, async () => true)).toBe("deferred");
  expect(calls).not.toContain("plugins remove --local --yes default");
  expect(await retireDefaultPlugin("/native/devin", home, run, async () => false)).toBe("removed");
  expect(calls).toContain("plugins remove --local --yes default");
  expect(await retireDefaultPlugin("/native/devin", home, run, async () => false)).toBe("absent");
});

test("a foreign default plugin and an unavailable inventory are never removed", async () => {
  const run = async (args: string[]) => args[1] === "list"
    ? { code: 0, stdout: "  • default v0.0.0\n", stderr: "" }
    : { code: 0, stdout: `Plugin: default\n  source: ${home}\n  description: unrelated plugin\n`, stderr: "" };
  expect(retireDefaultPlugin("/native/devin", home, run, async () => false)).rejects.toThrow("not the exact AgentRoles-owned Role");
  expect(await retireDefaultPlugin("/native/devin", home, async () => ({ code: 1, stdout: "", stderr: "login required" }), async () => false)).toBe("deferred");
});
