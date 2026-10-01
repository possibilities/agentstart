/** One bounded preparation worker; the ACP loop remains responsive under a root lock. */
import { parentPort, workerData } from "node:worker_threads";
import { lstatSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { owner, prepareDevinInvocation, resolveDevinGitRoot, saveInvocation } from "./devin-invocation.ts";
import type { ProcessIdentity } from "./devin-process.ts";

const { home, resources, state, child } = workerData as {
  home: string; resources: string; state: string; child: ProcessIdentity;
};
const roots = new Map<string, string>();
parentPort!.on("message", ({ sequence, cwd }: { sequence: number; cwd: string }) => {
  let repo: string;
  try { repo = resolveDevinGitRoot(cwd); }
  catch (error) {
    parentPort!.postMessage({ sequence, code: -32602, error: error instanceof Error ? error.message : String(error) });
    return;
  }
  try {
    if (!roots.has(repo)) {
      if (roots.size >= 256) throw new Error("ACP snapshot root capacity exceeded (256 roots)");
      const claim = prepareDevinInvocation(repo, home, resources, state);
      claim.invocation.child = child;
      saveInvocation(claim.record, claim.invocation);
      roots.set(repo, claim.invocation.snapshot);
      parentPort!.postMessage({ sequence, conflicts: claim.conflicts });
    } else {
      const directory = join(repo, ".devin"), marker = join(directory, "agentstart-owner.json");
      if (!lstatSync(directory).isDirectory() || lstatSync(directory).isSymbolicLink() ||
          !lstatSync(marker).isFile() || lstatSync(marker).isSymbolicLink() ||
          readFileSync(marker, "utf8") !== JSON.stringify({ owner, id: roots.get(repo) })) {
        throw new Error("project .devin ownership marker changed during the ACP process");
      }
      parentPort!.postMessage({ sequence });
    }
  } catch (error) {
    parentPort!.postMessage({ sequence, error: error instanceof Error ? error.message : String(error) });
  }
});
