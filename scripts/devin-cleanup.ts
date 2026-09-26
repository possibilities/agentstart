/** Periodic, conservative cleanup of AgentStart's in-place Devin Role snapshots. */
import { createHash } from "node:crypto";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync, rmSync, rmdirSync, unlinkSync } from "node:fs";
import { join, dirname } from "node:path";
import { invocationDir, owner, type Invocation } from "./devin-invocation.ts";
import { processIdentity, type ProcessIdentity } from "./devin-process.ts";

const recordName = /^[0-9a-f]{64}(?:\.json|-[0-9a-f-]{36}\.json)$/;
const uuidShape = /^[0-9a-f-]{36}$/;
const markerRel = "agentstart-owner.json";

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

type Stored = Omit<Invocation, "snapshot" | "created"> & { snapshot?: string; created?: boolean };
type Record_ = { path: string; value: Invocation };

export function cleanupDevinInvocations(dir = invocationDir(), lookup = processIdentity): number {
  if (!existsSync(dir)) return 0;
  if (!lstatSync(dir).isDirectory() || lstatSync(dir).isSymbolicLink()) throw new Error("Devin invocation state is not an owned directory");
  // One record per invocation; sessions sharing a Git root share its .devin
  // snapshot, so records reconcile per root rather than per file name.
  const groups = new Map<string, Record_[]>();
  for (const name of readdirSync(dir)) {
    if (!recordName.test(name)) continue;
    const record = join(dir, name);
    if (!lstatSync(record).isFile()) continue;
    let raw: Stored;
    try { raw = JSON.parse(readFileSync(record, "utf8")); }
    catch { console.error(`Devin cleanup: invalid record ${record}; left untouched`); continue; }
    // Records from the single-session format carry no snapshot or created flag:
    // their marker id was their own id and they only ever created directories.
    const snapshot = raw.snapshot ?? raw.id;
    const created = raw.created ?? true;
    const digest = createHash("sha256").update(typeof raw.cwd === "string" ? raw.cwd : "").digest("hex");
    if (raw.owner !== owner || typeof raw.id !== "string" || !uuidShape.test(raw.id) ||
        typeof snapshot !== "string" || !uuidShape.test(snapshot) || typeof created !== "boolean" ||
        typeof raw.cwd !== "string" || !raw.cwd.startsWith("/") ||
        (name !== `${digest}.json` && name !== `${digest}-${raw.id}.json`) ||
        !isIdentity(raw.wrapper) || (raw.child !== undefined && !isIdentity(raw.child)) ||
        (raw.files !== undefined && (typeof raw.files !== "object" || raw.files === null || Array.isArray(raw.files)))) {
      console.error(`Devin cleanup: unrecognized record ${record}; left untouched`);
      continue;
    }
    const value: Invocation = { ...raw, snapshot, created };
    const list = groups.get(raw.cwd) ?? [];
    list.push({ path: record, value });
    groups.set(raw.cwd, list);
  }
  let removed = 0;
  const drop = (rec: Record_) => { removeStaleTemp(rec.path, rec.value.id); unlinkSync(rec.path); removed++; };
  for (const [cwdPath, records] of groups) {
    // Any live wrapper or child in the group keeps the shared snapshot.
    if (records.some(rec => alive(rec.value.wrapper, lookup) || (rec.value.child && alive(rec.value.child, lookup)))) continue;
    let cwd: string;
    try { cwd = realpathSync(cwdPath); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      records.forEach(drop); continue;
    }
    if (cwd !== cwdPath) { console.error(`Devin cleanup: project path changed: ${cwdPath}`); continue; }
    const target = join(cwd, ".devin");
    if (!existsSync(target)) { records.forEach(drop); continue; }
    if (!lstatSync(target).isDirectory() || lstatSync(target).isSymbolicLink()) continue;
    const marker = join(target, markerRel);
    let claim: { owner?: string; id?: string };
    let markerText: string;
    try { markerText = readFileSync(marker, "utf8"); claim = JSON.parse(markerText); }
    catch { console.error(`Devin cleanup: missing or changed ownership marker: ${target}`); continue; }
    if (claim.owner !== owner || typeof claim.id !== "string" || !uuidShape.test(claim.id) || markerText !== JSON.stringify({ owner, id: claim.id })) continue;
    // The marker's id names one snapshot generation. Records from a superseded
    // generation are done — whatever of theirs survived reads as project files.
    const applicable = records.filter(rec => rec.value.snapshot === claim.id);
    const stale = records.filter(rec => rec.value.snapshot !== claim.id);
    if (!applicable.length) { console.error(`Devin cleanup: snapshot ${claim.id} has no invocation record for ${cwdPath}`); continue; }
    stale.forEach(drop);
    if (applicable.every(rec => rec.value.files === undefined)) {
      // A record that died before its manifest finished has no file list. When
      // it created the directory, the whole marked staging area is AgentStart's;
      // otherwise only the verified marker is ours to remove.
      if (applicable.some(rec => rec.value.created)) {
        rmSync(target, { recursive: true });
      } else {
        unlinkSync(marker);
        try { rmdirSync(target); }
        catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOTEMPTY") throw error; }
      }
      applicable.forEach(drop);
      continue;
    }
    // Every live session claimed the same render; records that saw less of it
    // contribute the same hashes, so the union is the snapshot manifest.
    const union = new Map<string, string>();
    const disputed = new Set<string>();
    for (const rec of applicable) {
      for (const [relative, hash] of Object.entries(rec.value.files ?? {})) {
        if (union.has(relative) && union.get(relative) !== hash) disputed.add(relative);
        else union.set(relative, hash);
      }
    }
    for (const relative of disputed) union.delete(relative);
    if ([...union.entries()].some(([relative, hash]) => !relative || relative.startsWith("/") || relative.includes("\0") ||
        relative.split("/").some(part => !part || part === "." || part === "..") || !/^[0-9a-f]{64}$/.test(hash))) continue;
    if (fileHash(marker) !== union.get(markerRel)) continue;
    // Delete only files whose bytes still match the snapshot. Unknown and edited
    // content belongs to the project, not to the cleanup job.
    for (const [relative, hash] of [...union.entries()].filter(([path]) => path !== markerRel)) {
      const path = safeFile(target, relative);
      if (path && fileHash(path) === hash) unlinkSync(path);
    }
    const directories = new Set<string>([target]);
    for (const [relative] of union) {
      let path = dirname(join(target, relative));
      while (path !== target) { directories.add(path); path = dirname(path); }
    }
    for (const path of [...directories].filter(path => path !== target).sort((a, b) => b.length - a.length)) {
      try { rmdirSync(path); } catch (error) { if (!["ENOTEMPTY", "ENOENT", "EEXIST", "ENOTDIR"].includes((error as NodeJS.ErrnoException).code ?? "")) throw error; }
    }
    unlinkSync(marker);
    try { rmdirSync(target); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOTEMPTY") throw error;
      console.error(`Devin cleanup: preserved new or modified project files in ${target}`);
    }
    applicable.forEach(drop);
  }
  return removed;
}
