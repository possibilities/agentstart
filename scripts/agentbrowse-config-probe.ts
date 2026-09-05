// Parse one agentbrowse config with a checkout's own loader and report only the
// loader's verdict. Run by scripts/agentbrowse-config before it links the
// tracked config, so a shape the deployed CLI rejects fails the install by name
// instead of silently taking every browser-backed fetch down.
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [loaderPath, configPath] = process.argv.slice(2);
if (!loaderPath || !configPath) {
  console.error("usage: agentbrowse-config-probe.ts <config/deployment.ts> <config.json>");
  process.exit(64);
}

const loader = (await import(pathToFileURL(loaderPath).href)) as {
  loadAgentbrowseConfig?: (env: Record<string, string | undefined>) => unknown;
};
if (typeof loader.loadAgentbrowseConfig !== "function") {
  console.error(`${loaderPath} does not export loadAgentbrowseConfig`);
  process.exit(1);
}
try {
  // The real loader insists on an absolute path; a relative one is the caller's convenience.
  loader.loadAgentbrowseConfig({ ...process.env, AGENTBROWSE_CONFIG: resolve(configPath) });
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
