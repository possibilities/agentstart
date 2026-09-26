/** Periodic, conservative cleanup of AgentStart's in-place Devin Role snapshots. */
import { createHash } from "node:crypto";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync, rmSync, rmdirSync, unlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { invocationDir, invocationPath, owner, type Invocation } from "./devin-invocation.ts";
import { processIdentity, type ProcessIdentity } from "./devin-process.ts";

function isIdentity(value: unknown): value is ProcessIdentity {
  const item = value as ProcessIdentity;
  return !!item && Number.isSafeInteger(item.pid) && item.pid > 0 && typeof item.started === "string" && /^\d+\.\d{6}$/.test(item.started);
}
function alive(identity: ProcessIdentity, lookup: (pid: number) => ProcessIdentity | null): boolean {
  const current = lookup(identity.pid);
  return current !== null && current.started === identity.started;
}
function fileHash(path: string): string | null {
  try {
    if (!lstatSync(path).isFile()) return null;
    return createHash("sha256").update(readFileSync(path)).digest("hex");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

function safeFile(target: string, relative: string): string | null {
  let directory = target;
  const parts = relative.split("/");
  for (const part of parts.slice(0, -1)) {
    directory = join(directory, part);
    try {
      const stat = lstatSync(directory);
      if (!stat.isDirectory() || stat.isSymbolicLink()) return null;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
  }
  return join(directory, parts.at(-1)!);
}

function removeStaleTemp(record: string, id: string): void {
  const temp = `${record}.${id}.tmp`;
  try { if (lstatSync(temp).isFile()) unlinkSync(temp); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
}

export function cleanupDevinInvocations(dir = invocationDir(), lookup = processIdentity): number {
  if (!existsSync(dir)) return 0;
  if (!lstatSync(dir).isDirectory() || lstatSync(dir).isSymbolicLink()) throw new Error("Devin invocation state is not an owned directory");
  let removed = 0;
  for (const name of readdirSync(dir)) {
    if (!/^[0-9a-f]{64}\.json$/.test(name)) continue;
    const record = join(dir, name);
    if (!lstatSync(record).isFile()) continue;
    let value: Invocation;
    try { value = JSON.parse(readFileSync(record, "utf8")); }
    catch { console.error(`Devin cleanup: invalid record ${record}; left untouched`); continue; }
    if (value.owner !== owner || !/^[0-9a-f-]{36}$/.test(value.id) || typeof value.cwd !== "string" ||
        !value.cwd.startsWith("/") || invocationPath(dir, value.cwd) !== record || !isIdentity(value.wrapper) ||
        (value.child !== undefined && !isIdentity(value.child))) {
      console.error(`Devin cleanup: unrecognized record ${record}; left untouched`);
      continue;
    }
    if (alive(value.wrapper, lookup) || (value.child && alive(value.child, lookup))) continue;
    let cwd: string;
    try { cwd = realpathSync(value.cwd); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      removeStaleTemp(record, value.id); unlinkSync(record); removed++; continue;
    }
    if (cwd !== value.cwd) { console.error(`Devin cleanup: project path changed: ${value.cwd}`); continue; }
    const target = join(cwd, ".devin");
    if (!existsSync(target)) { removeStaleTemp(record, value.id); unlinkSync(record); removed++; continue; }
    if (!lstatSync(target).isDirectory() || lstatSync(target).isSymbolicLink()) continue;
    const marker = join(target, "agentstart-owner.json");
    let claim: { owner?: string; id?: string };
    let markerText: string;
    try { markerText = readFileSync(marker, "utf8"); claim = JSON.parse(markerText); }
    catch { console.error(`Devin cleanup: missing or changed ownership marker: ${target}`); continue; }
    if (claim.owner !== owner || claim.id !== value.id || markerText !== JSON.stringify({ owner, id: value.id })) continue;
    if (!value.files || !Object.keys(value.files).length) {
      // The wrapper died while preparing the snapshot, before it ever launched
      // Devin. This entire marked directory is its incomplete staging output.
      rmSync(target, { recursive: true });
      removeStaleTemp(record, value.id);
      unlinkSync(record);
      removed++;
      continue;
    }
    const files = Object.entries(value.files);
    if (fileHash(marker) !== value.files["agentstart-owner.json"]) continue;
    if (files.some(([relative, hash]) => !relative || relative.startsWith("/") || relative.includes("\0") ||
        relative.split("/").some(part => !part || part === "." || part === "..") || !/^[0-9a-f]{64}$/.test(hash))) continue;
    // Delete only files whose bytes still match the snapshot. Unknown and edited
    // content belongs to the project, not to the cleanup job.
    for (const [relative, hash] of files.filter(([path]) => path !== "agentstart-owner.json")) {
      const path = safeFile(target, relative);
      if (path && fileHash(path) === hash) unlinkSync(path);
    }
    const directories = new Set<string>([target]);
    for (const [relative] of files) {
      let path = dirname(join(target, relative));
      while (path !== target) { directories.add(path); path = dirname(path); }
    }
    for (const path of [...directories].filter(path => path !== target).sort((a, b) => b.length - a.length)) {
      try { rmdirSync(path); } catch (error) { if (!["ENOTEMPTY", "ENOENT", "EEXIST", "ENOTDIR"].includes((error as NodeJS.ErrnoException).code ?? "")) throw error; }
    }
    if (fileHash(marker) === value.files["agentstart-owner.json"]) unlinkSync(marker);
    try { rmdirSync(target); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOTEMPTY") throw error;
      console.error(`Devin cleanup: preserved new or modified project files in ${target}`);
    }
    removeStaleTemp(record, value.id);
    unlinkSync(record);
    removed++;
  }
  return removed;
}
