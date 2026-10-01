/** Opt-in ACP transport: prepare Role resources before native session admission. */
import { spawn } from "node:child_process";
import { once } from "node:events";
import { homedir } from "node:os";
import { join } from "node:path";
import { Worker } from "node:worker_threads";
import type { Readable, Writable } from "node:stream";
import { invocationDir } from "./devin-invocation.ts";
import { processIdentity } from "./devin-process.ts";

// Native output is framed too: a local rejection must never splice into a
// partially received native response. Accepted frames retain their exact bytes.
const maxFrameBytes = 8 * 1024 * 1024;
const maxPendingAdmissions = 32;
const maxPendingBytes = 16 * 1024 * 1024;

async function* frames(input: Readable): AsyncGenerator<Buffer> {
  let parts: Buffer[] = [], size = 0;
  for await (const chunk of input) {
    const bytes = Buffer.from(chunk);
    let start = 0;
    while (start < bytes.length) {
      const newline = bytes.indexOf(10, start);
      const end = newline === -1 ? bytes.length : newline + 1;
      size += end - start;
      if (size > maxFrameBytes) throw new Error("ACP frame exceeds 8 MiB");
      parts.push(bytes.subarray(start, end));
      if (newline !== -1) {
        yield Buffer.concat(parts, size);
        parts = []; size = 0;
      }
      start = end;
    }
  }
  // ACP is newline-delimited. Do not silently admit a truncated request.
  if (size) throw new Error("ACP stream ended with an unterminated frame");
}

async function write(output: Writable, bytes: Buffer): Promise<void> {
  if (!output.write(bytes)) await once(output, "drain");
}

type Pending = { frame: Buffer; id: string | number };
type Prepared = { sequence: number; error?: string; code?: number; conflicts?: string[] };

export async function runDevinAcp(native: string, args: string[], env: NodeJS.ProcessEnv): Promise<number> {
  const child = spawn(native, args, { cwd: process.cwd(), env, stdio: ["pipe", "pipe", "inherit"] });
  let ended = false;
  const exited = new Promise<number>((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => { ended = true; resolve(code ?? (signal === "SIGINT" ? 130 : signal === "SIGHUP" ? 129 : 143)); });
  });
  // Attach a rejection handler immediately, including failures before setup.
  void exited.catch(() => {});
  const home = env.HOME ?? homedir();
  let worker: Worker;
  try {
    const identity = child.pid && processIdentity(child.pid);
    if (!identity) throw new Error("could not identify the native Devin ACP process");
    worker = new Worker(new URL("./devin-acp-prepare.ts", import.meta.url), { workerData: {
      home, resources: env.AGENTSTART_RESOURCES_ROOT ?? join(home, ".local/share/agentstart/resources"),
      state: invocationDir(env), child: identity,
    } });
  } catch (error) {
    child.kill("SIGKILL"); await exited;
    throw error;
  }
  const pending = new Map<number, Pending>();
  let pendingBytes = 0, sequence = 0;
  let output = Promise.resolve(), admissionWrites = Promise.resolve();
  let stopping = false, failed = false, grace: ReturnType<typeof setTimeout> | undefined;
  const stop = (signal: NodeJS.Signals = "SIGTERM") => {
    if (!ended) child.kill(signal);
    if (!stopping) {
      stopping = true;
      // EOF or a signal must not leave a native process holding snapshot refs.
      grace = setTimeout(() => { if (!ended) child.kill("SIGKILL"); }, 2000);
      grace.unref();
    }
  };
  const fail = (error: unknown) => {
    failed = true;
    console.error(`AgentStart Devin ACP: ${error instanceof Error ? error.message : String(error)}`);
    stop();
  };
  const emit = (bytes: Buffer) => {
    output = output.then(() => write(process.stdout, bytes));
    void output.catch(fail);
    return output;
  };
  const reject = (id: string | number | null, code: number, message: string) => emit(Buffer.from(
    JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n"));
  const onPrepared = (result: Prepared) => {
    const request = pending.get(result.sequence);
    if (!request) return;
    if (ended || stopping) return;
    const release = () => { pending.delete(result.sequence); pendingBytes -= request.frame.length; };
    if (result.error) {
      void reject(request.id, result.code ?? -32000, result.code === -32602
        ? "cwd must be an absolute existing directory in a Git repository"
        : "AgentStart Devin Role snapshot preparation failed").then(release, fail);
      console.error(`AgentStart Devin ACP: ${result.error}`); return;
    }
    for (const path of (result.conflicts ?? []).slice(0, 5)) console.error(`Kept existing .devin/${path}; it is not part of the snapshot.`);
    if ((result.conflicts?.length ?? 0) > 5) console.error(`Kept ${result.conflicts!.length - 5} more existing .devin entries.`);
    admissionWrites = admissionWrites.then(async () => {
      if (!ended && !stopping) await write(child.stdin, request.frame);
      release();
    });
    void admissionWrites.catch(fail);
  };
  worker.on("message", onPrepared);
  worker.on("error", fail);
  worker.on("exit", code => { if (!stopping && !ended) fail(new Error(`ACP preparation worker exited (${code})`)); });
  // Pipe errors are lifecycle failures, never uncaught process errors.
  child.stdin.on("error", fail);
  process.stdout.on("error", fail);
  const handlers = new Map<NodeJS.Signals, () => void>();
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
    const handler = () => stop(signal);
    handlers.set(signal, handler); process.on(signal, handler);
  }
  const incoming = (async () => {
    for await (const frame of frames(process.stdin)) {
      if (ended || stopping) break;
      let rpc: Record<string, unknown>;
      try { rpc = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(frame)); }
      catch { await reject(null, -32700, "Parse error"); continue; }
      if (!rpc || typeof rpc !== "object" || Array.isArray(rpc)) { await reject(null, -32600, "Invalid Request"); continue; }
      if (rpc.method !== "session/new" && rpc.method !== "session/load") {
        // Responses, notifications, extensions and permission answers retain the
        // native protocol. In particular, this proxy never answers approvals.
        await write(child.stdin, frame); continue;
      }
      const id = rpc.id;
      if (rpc.jsonrpc !== "2.0" || !(typeof id === "string" || (typeof id === "number" && Number.isSafeInteger(id)))) {
        await reject(null, -32600, "Invalid Request"); continue;
      }
      const params = rpc.params as { cwd?: unknown } | null;
      if (!params || typeof params !== "object" || Array.isArray(params) || typeof params.cwd !== "string" ||
          !params.cwd.startsWith("/") || params.cwd.includes("\0")) {
        await reject(id, -32602, "cwd must be an absolute existing directory in a Git repository"); continue;
      }
      if (pending.size >= maxPendingAdmissions || pendingBytes + frame.length > maxPendingBytes) {
        await reject(id, -32000, "AgentStart Devin Role admission capacity exceeded"); continue;
      }
      const key = ++sequence;
      pending.set(key, { frame, id }); pendingBytes += frame.length;
      worker.postMessage({ sequence: key, cwd: params.cwd });
    }
    // All frames already sent to native have been flushed. Pending preparations
    // do not authorize a session after its controller has closed the transport.
    await admissionWrites;
    child.stdin.end();
    stop();
  })().catch(error => { if (!ended && !stopping) fail(error); });
  const outgoing = (async () => {
    for await (const frame of frames(child.stdout)) await emit(frame);
  })().catch(fail);
  try {
    const code = await exited;
    // Node's exit precedes pipe close: drain the native's last protocol frames.
    await outgoing; await output;
    return failed ? 1 : code;
  } finally {
    stop();
    if (grace) clearTimeout(grace);
    for (const [signal, handler] of handlers) process.off(signal, handler);
    process.stdout.off("error", fail);
    // This CLI owns its stdin reader. Close it when native exits even if the
    // controller kept the input pipe open; otherwise the wrapper never exits.
    process.stdin.destroy();
    await incoming;
    worker.removeListener("message", onPrepared);
    await worker.terminate();
    pending.clear();
  }
}
