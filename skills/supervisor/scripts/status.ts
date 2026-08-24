#!/usr/bin/env bun

import { parseArgs } from "node:util";
import { DirectOwnership, defaultSocketPath } from "./ade.ts";
import { defaultProjectRoots, normalizePath } from "./git.ts";
import { buildRoster } from "./roster.ts";

/**
 * The roster on demand.
 *
 * The watcher emits one of these when it starts; this prints the same object
 * whenever it is asked for — above all when the supervisor is winding down, so
 * a run ends with the standing picture rather than only the events that
 * happened to fire while it was awake.
 */

function usage(): string {
  return `Usage: status.ts [--project-root <path>]... [--socket <path>] [--occasion <label>]

Prints one roster JSON object: every worktree under the project roots, each
placed as watching, landed, or removable, with the live agent session in it
when an agent development environment can name one.
`;
}

const parsed = parseArgs({
  args: process.argv.slice(2),
  options: {
    "project-root": { type: "string", multiple: true },
    socket: { type: "string" },
    occasion: { type: "string" },
    help: { type: "boolean", short: "h", default: false },
  },
  strict: true,
});

if (parsed.values.help) {
  process.stdout.write(usage());
  process.exit(0);
}

const roots = (parsed.values["project-root"] ?? defaultProjectRoots()).map(normalizePath);
const ownership = new DirectOwnership(
  parsed.values.socket ?? defaultSocketPath(),
  process.env.HERDR_PANE_ID ?? null,
);
const roster = await buildRoster(roots, ownership, parsed.values.occasion ?? "requested");
process.stdout.write(`${JSON.stringify(roster)}\n`);
