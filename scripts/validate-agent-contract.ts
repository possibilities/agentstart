#!/usr/bin/env bun

/**
 * Validate one fleet agent contract — the document a CLI publishes as
 * `<cli> guide --json`.
 *
 * config/agent-contract/schema.json is normative and this script EXECUTES it,
 * through the small interpreter in json-schema-subset.ts. It does not restate
 * the schema's rules: an earlier version did, and drifted from it in nine
 * places in both directions while claiming the schema was authoritative. Two
 * authorships of one set of rules is the disease this contract exists to cure.
 *
 * What lives here is only what JSON Schema cannot say — the agreements that
 * span fields, and the command tree's full-path semantics.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { validateAgainstSchema, type Violation } from "./json-schema-subset.ts";

const SCHEMA_PATH = join(dirname(import.meta.dir), "config", "agent-contract", "schema.json");

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

interface Leaf {
  path: string;
  command: Json;
}

/**
 * Walk the command forest, yielding every node with its full space-joined path.
 * `groom export` and `artifacts list` are paths, not names — which is exactly
 * what AgentBoard's guide already publishes in read_only_commands today.
 */
function walk(commands: unknown, prefix: string[], into: Leaf[], groups: Leaf[]): void {
  if (!Array.isArray(commands)) return;
  for (const command of commands) {
    if (!isObject(command)) continue;
    const name = typeof command["name"] === "string" ? command["name"] : "?";
    const path = [...prefix, name];
    const subcommands = command["subcommands"];
    if (Array.isArray(subcommands) && subcommands.length > 0) {
      groups.push({ path: path.join(" "), command });
      walk(subcommands, path, into, groups);
    } else {
      into.push({ path: path.join(" "), command });
    }
  }
}

function argumentNames(command: Json): string[] {
  const args = command["arguments"];
  if (!Array.isArray(args)) return [];
  return args
    .filter(isObject)
    .map((argument) => argument["name"])
    .filter((name): name is string => typeof name === "string");
}

/** The agreements JSON Schema cannot state. */
function crossFieldViolations(data: Json): Violation[] {
  const out: Violation[] = [];
  const leaves: Leaf[] = [];
  const groups: Leaf[] = [];
  walk(data["commands"], [], leaves, groups);

  const at = (path: string, message: string) => out.push({ path, message });

  // Sibling names must be unique at each level, or a path is ambiguous.
  const byParent = new Map<string, Set<string>>();
  for (const node of [...leaves, ...groups]) {
    const segments = node.path.split(" ");
    const parent = segments.slice(0, -1).join(" ");
    const own = segments[segments.length - 1]!;
    const seen = byParent.get(parent) ?? new Set<string>();
    if (seen.has(own)) at(`commands.${node.path}`, "duplicates a sibling command name");
    seen.add(own);
    byParent.set(parent, seen);
  }

  const duplicated = out.length > 0;
  const leafPaths = leaves.map((leaf) => leaf.path);
  const nonMutating = leaves
    .filter((leaf) => leaf.command["mutates"] === false)
    .map((leaf) => leaf.path);

  // read_only_commands must be exactly the non-mutating leaves, by full path.
  // A duplicate name makes every path ambiguous, so the cross-check below
  // would compare against a list that names one thing twice — a duplicate pair
  // straddling `mutates` would satisfy it. Report the duplicate and stop.
  const concepts = data["concepts"];
  if (!duplicated && isObject(concepts) && Array.isArray(concepts["read_only_commands"])) {
    const declared = concepts["read_only_commands"] as unknown[];
    for (const entry of declared) {
      if (typeof entry !== "string") continue;
      if (!leafPaths.includes(entry)) {
        at("concepts.read_only_commands", `names "${entry}", which is not a command`);
      } else if (!nonMutating.includes(entry)) {
        at("concepts.read_only_commands", `names "${entry}", which declares mutates: true`);
      }
    }
    for (const path of nonMutating) {
      if (!declared.includes(path)) {
        at("concepts.read_only_commands", `omits "${path}", which declares mutates: false`);
      }
    }
  }

  const meta = data["meta"];
  const cliAudience = isObject(meta) ? meta["audience"] : undefined;

  for (const { path, command } of [...leaves, ...groups]) {
    const where = `commands.${path}`;

    if (cliAudience === "operator" && command["audience"] === "agent") {
      at(`${where}.audience`, "is agent, but the CLI declares meta.audience operator");
    }

    // A flag must wear its dashes and a positional must not: the slip produces
    // an argument no caller can pass, and it is the most common one.
    const args = Array.isArray(command["arguments"]) ? command["arguments"] : [];
    const seenArgs = new Set<string>();
    for (const argument of args) {
      if (!isObject(argument)) continue;
      const name = argument["name"];
      if (typeof name !== "string") continue;
      const spellings = [name, ...(Array.isArray(argument["aliases"]) ? argument["aliases"] : [])];
      for (const spelling of spellings) {
        if (typeof spelling !== "string") continue;
        if (seenArgs.has(spelling)) {
          at(`${where}.arguments`, `declares "${spelling}" twice, counting aliases`);
        }
        seenArgs.add(spelling);
      }
      const looksLikeFlag = name.startsWith("-");
      if (argument["positional"] === true && looksLikeFlag) {
        at(`${where}.arguments.${name}`, "a positional must not carry leading dashes");
      }
      if (argument["positional"] !== true && !looksLikeFlag) {
        at(`${where}.arguments.${name}`, "a flag must carry its leading dashes, or be marked positional");
      }
      if (argument["direction"] !== undefined && argument["format"] !== "path") {
        at(`${where}.arguments.${name}`, "direction applies only to format: path");
      }
    }

    // A constraint that names an argument the command does not have is a
    // silent no-op, which is worse than an error.
    const constraints = Array.isArray(command["constraints"]) ? command["constraints"] : [];
    for (const constraint of constraints) {
      if (!isObject(constraint)) continue;
      const named = Array.isArray(constraint["arguments"]) ? constraint["arguments"] : [];
      for (const name of named) {
        if (typeof name === "string" && !seenArgs.has(name)) {
          at(`${where}.constraints`, `names "${name}", which this command does not accept`);
        }
      }
    }

    // An out-of-process caller has no pipe. A command that can only be fed
    // through stdin is unreachable, so an agent verb may not require it.
    const stdin = command["stdin"];
    if (isObject(stdin) && stdin["required"] === true && command["audience"] === "agent") {
      at(
        `${where}.stdin`,
        "is required on an agent command, which has no pipe; accept the content inline too",
      );
    }
  }

  // Global arguments obey the same dash rule.
  const globals = Array.isArray(data["global_arguments"]) ? data["global_arguments"] : [];
  for (const argument of globals) {
    if (!isObject(argument)) continue;
    const name = argument["name"];
    if (typeof name !== "string") continue;
    if (argument["positional"] !== true && !name.startsWith("-")) {
      at(`global_arguments.${name}`, "a flag must carry its leading dashes");
    }
  }

  return out;
}

export function validateContract(envelope: unknown, schema?: Json): readonly string[] {
  const root = schema ?? (JSON.parse(readFileSync(SCHEMA_PATH, "utf8")) as Json);
  const shape = validateAgainstSchema(root, envelope);
  const problems = shape.map((v) => `${v.path || "$"}: ${v.message}`);
  // Cross-field checks assume a well-shaped document; running them on a
  // malformed one produces noise that buries the real fault.
  if (shape.length > 0) return problems;
  const data = (envelope as Json)["data"];
  if (!isObject(data)) return problems;
  return crossFieldViolations(data).map((v) => `${v.path}: ${v.message}`);
}

function usage(): never {
  process.stderr.write("Usage: validate-agent-contract.ts <cli-name> | --file <contract.json>\n");
  process.exit(2);
}

function main(argv: readonly string[]): number {
  if (argv.length === 0) usage();
  if (argv[0] === "-h" || argv[0] === "--help") {
    process.stdout.write(
      "Usage: validate-agent-contract.ts <cli-name> | --file <contract.json>\n\n" +
        "Validates one fleet agent contract against config/agent-contract/schema.json.\n",
    );
    return 0;
  }
  if (argv[0]!.startsWith("-") && argv[0] !== "--file") usage();

  let raw: string;
  let source: string;

  if (argv[0] === "--file") {
    const path = argv[1];
    if (path === undefined) usage();
    source = path;
    try {
      raw = readFileSync(path, "utf8");
    } catch {
      process.stderr.write(`agent contract: cannot read ${path}\n`);
      return 1;
    }
  } else {
    const cli = argv[0]!;
    source = `${cli} guide --json`;
    let run: { success: boolean; exitCode: number | null; stdout: Buffer; stderr: Buffer };
    try {
      run = Bun.spawnSync([cli, "guide", "--json"], { stdout: "pipe", stderr: "pipe" });
    } catch {
      process.stderr.write(`agent contract: no such command "${cli}" on PATH\n`);
      return 1;
    }
    if (!run.success) {
      process.stderr.write(
        `agent contract: \`${source}\` failed (exit ${run.exitCode})\n${run.stderr.toString()}`,
      );
      return 1;
    }
    raw = run.stdout.toString();
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    process.stderr.write(`agent contract: ${source} did not emit JSON: ${String(error)}\n`);
    return 1;
  }

  const problems = validateContract(parsed);
  if (problems.length > 0) {
    process.stderr.write(`agent contract: ${source} is not conformant\n`);
    for (const problem of problems) process.stderr.write(`  ${problem}\n`);
    return 1;
  }
  process.stdout.write(`agent contract: ${source} conforms to version 1\n`);
  return 0;
}

if (import.meta.main) process.exit(main(process.argv.slice(2)));
