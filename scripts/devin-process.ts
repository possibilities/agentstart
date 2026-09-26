/** Darwin process identity: PID plus kernel start time (microseconds), not PID alone. */
import { dlopen, ptr } from "bun:ffi";

const libproc = process.platform === "darwin" ? dlopen("/usr/lib/libproc.dylib", {
  proc_pidinfo: { args: ["i32", "i32", "u64", "ptr", "i32"], returns: "i32" },
}) : null;

export type ProcessIdentity = { pid: number; started: string };

export function processIdentity(pid: number): ProcessIdentity | null {
  if (!libproc) throw new Error("Devin invocation cleanup requires macOS libproc");
  if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error("invalid process ID");
  // proc_bsdinfo on Darwin: sizeof 136, pbi_start_tvsec at 120,
  // pbi_start_tvusec at 128. Unlike ps lstart this distinguishes same-second reuse.
  const buffer = Buffer.alloc(136);
  const bytes = libproc.symbols.proc_pidinfo(pid, 3, 0, ptr(buffer), buffer.length);
  if (bytes === 0) return null;
  if (bytes !== buffer.length) throw new Error(`could not inspect process ${pid}`);
  const seconds = buffer.readBigUInt64LE(120);
  const micros = buffer.readBigUInt64LE(128);
  if (seconds === 0n || micros >= 1_000_000n) throw new Error(`invalid process start time for ${pid}`);
  return { pid, started: `${seconds}.${micros.toString().padStart(6, "0")}` };
}
