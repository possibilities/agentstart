// Stand-in for agentbrowse's config loader in tests: accepts the tracked shape
// and rejects an Apple backend with more than one target, the exact drift that
// took the browser fleet down on 2026-09-05.
import { readFileSync } from "node:fs";

export function loadAgentbrowseConfig(
  env: Record<string, string | undefined> = process.env,
): unknown {
  const path = env.AGENTBROWSE_CONFIG;
  if (!path) throw new Error("AGENTBROWSE_CONFIG is required");
  const root = JSON.parse(readFileSync(path, "utf8")) as {
    backends?: { type?: string; maxTargets?: number }[];
  };
  (root.backends ?? []).forEach((backend, index) => {
    if (backend.type === "apple-container" && (backend.maxTargets ?? 1) !== 1) {
      throw new Error(`${path}: backends[${index}].maxTargets must be 1`);
    }
  });
  return root;
}
