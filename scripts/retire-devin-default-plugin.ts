#!/usr/bin/env bun
/** Exact, conditional cutover from AgentRoles' sticky default plugin. Called by install-harness-shims only. */
import { execFile } from "node:child_process";
import { basename, join } from "node:path";
import { realpathSync } from "node:fs";

type Result = { code: number; stdout: string; stderr: string };
type Runner = (args: string[]) => Promise<Result>;

function command(binary: string): Runner {
  return (args) => new Promise((resolve) => execFile(binary, args, { timeout: 15_000, maxBuffer: 100_000 }, (error, stdout, stderr) =>
    resolve({ code: error ? Number((error as { code?: number }).code) || 1 : 0, stdout, stderr })));
}

async function activeDevin(): Promise<boolean> {
  const output = await new Promise<string>((resolve, reject) => execFile("ps", ["-axo", "pid=,comm=,command="], { timeout: 3_000, maxBuffer: 2_000_000 },
    (error, stdout) => error ? reject(new Error("cannot inspect active Devin processes")) : resolve(stdout)));
  return output.split("\n").some((line) => {
    const match = /^\s*(\d+)\s+(\S+)\s+(.*)$/.exec(line);
    if (!match || Number(match[1]) === process.pid) return false;
    return basename(match[2]!) === "devin" || /(?:^|\s)\S*\/bin\/devin(?:\s|$)/.test(match[3]!);
  });
}

export async function retireDefaultPlugin(native: string, home: string, run: Runner = command(native), active = activeDevin): Promise<"absent" | "removed" | "deferred"> {
  const listed = await run(["plugins", "list"]);
  if (listed.code !== 0) return "deferred"; // A fresh install may not have a login yet. Never treat it as permission to remove.
  if (!/^\s*• default v0\.0\.0\s*$/m.test(listed.stdout)) return "absent";
  const info = await run(["plugins", "info", "default"]);
  if (info.code !== 0) throw new Error("cannot verify installed default Devin plugin before removal");
  const source = /^\s*source:\s*(.+)\s*$/m.exec(info.stdout)?.[1]?.trim();
  const expected = realpathSync(join(home, ".cache", "agentroles", "devin", "default"));
  if (!source || realpathSync(source) !== expected ||
      !info.stdout.includes(`description: agentroles role default (${join(home, ".local/share/agentstart/resources/roles/default")})`))
    throw new Error("default Devin plugin is not the exact AgentRoles-owned Role; leaving it installed");
  if (await active()) return "deferred";
  const removed = await run(["plugins", "remove", "--local", "--yes", "default"]);
  if (removed.code !== 0) throw new Error("native Devin refused exact local default plugin removal");
  const after = await run(["plugins", "list"]);
  if (after.code !== 0 || /^\s*• default v0\.0\.0\s*$/m.test(after.stdout)) throw new Error("default Devin plugin removal could not be verified");
  return "removed";
}

if (import.meta.main) {
  const [native, home] = process.argv.slice(2);
  if (!native || !home) { console.error("usage: retire-devin-default-plugin NATIVE HOME"); process.exitCode = 64; }
  else try {
    const result = await retireDefaultPlugin(native, home);
    console.error(`AgentStart Devin plugin cutover: ${result}`);
  } catch (error) { console.error(`AgentStart Devin plugin cutover: ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; }
}
