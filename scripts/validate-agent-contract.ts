#!/usr/bin/env bun

/**
 * Validate one fleet agent contract — the document a CLI publishes as
 * `<cli> guide --json`.
 *
 * config/agent-contract/schema.json is normative; this script is a
 * dependency-free implementation of the same rules, because AgentStart carries
 * no package.json and a JSON Schema library is not worth acquiring one. Every
 * rule below names the schema construct it mirrors, and tests/agent-contract.test.ts
 * asserts that a fixture violating each rule is actually rejected — that pairing
 * is what keeps the two from drifting.
 *
 * It additionally enforces the cross-field agreements JSON Schema cannot state:
 * read_only_commands must be exactly the non-mutating commands, and an
 * agent-audience command may not appear in an operator-audience CLI.
 */

import { readFileSync } from "node:fs";

const SCALARS = new Set(["string", "boolean", "integer", "number"]);
const FORMATS = new Set(["path", "url", "duration", "ref", "json", "csv"]);
const CLI_AUDIENCES = new Set(["agent", "operator"]);
const COMMAND_AUDIENCES = new Set(["agent", "operator", "internal"]);

type Json = Record<string, unknown>;

class Problems {
  private readonly found: string[] = [];

  at(path: string, message: string): void {
    this.found.push(`${path}: ${message}`);
  }

  get list(): readonly string[] {
    return this.found;
  }
}

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireString(p: Problems, at: string, value: unknown): void {
  if (typeof value !== "string" || value.length === 0) p.at(at, "must be a non-empty string");
}

/** $defs/argument */
function checkArgument(p: Problems, at: string, arg: unknown): void {
  if (!isObject(arg)) {
    p.at(at, "must be an object");
    return;
  }
  const allowed = new Set([
    "name", "type", "description", "format", "required",
    "positional", "repeatable", "choices", "default", "aliases",
  ]);
  for (const key of Object.keys(arg)) {
    if (!allowed.has(key)) p.at(`${at}.${key}`, "is not a contract field");
  }
  requireString(p, `${at}.name`, arg["name"]);
  requireString(p, `${at}.description`, arg["description"]);
  if (typeof arg["type"] !== "string" || !SCALARS.has(arg["type"])) {
    p.at(`${at}.type`, `must be one of ${[...SCALARS].join(", ")}`);
  }
  if (arg["format"] !== undefined && (typeof arg["format"] !== "string" || !FORMATS.has(arg["format"]))) {
    p.at(`${at}.format`, `must be one of ${[...FORMATS].join(", ")}`);
  }
  for (const flag of ["required", "positional", "repeatable"]) {
    if (arg[flag] !== undefined && typeof arg[flag] !== "boolean") {
      p.at(`${at}.${flag}`, "must be a boolean");
    }
  }
  if (arg["choices"] !== undefined) {
    const choices = arg["choices"];
    if (!Array.isArray(choices) || choices.length === 0) {
      p.at(`${at}.choices`, "must be a non-empty array when present");
    } else if (choices.some((c) => typeof c !== "string")) {
      p.at(`${at}.choices`, "must contain only strings");
    }
  }
  // A positional named like a flag is the single most common authoring slip:
  // it silently produces an MCP argument nobody can pass.
  const name = arg["name"];
  if (typeof name === "string") {
    const looksLikeFlag = name.startsWith("-");
    if (arg["positional"] === true && looksLikeFlag) {
      p.at(`${at}.name`, "a positional must not carry leading dashes");
    }
    if (arg["positional"] !== true && !looksLikeFlag) {
      p.at(`${at}.name`, "a flag must carry its leading dashes, or be marked positional");
    }
  }
}

/** $defs/command */
function checkCommand(p: Problems, at: string, command: unknown): string | undefined {
  if (!isObject(command)) {
    p.at(at, "must be an object");
    return undefined;
  }
  const allowed = new Set(["name", "summary", "audience", "mutates", "guidance", "arguments"]);
  for (const key of Object.keys(command)) {
    if (!allowed.has(key)) p.at(`${at}.${key}`, "is not a contract field");
  }
  requireString(p, `${at}.name`, command["name"]);
  requireString(p, `${at}.summary`, command["summary"]);
  if (typeof command["audience"] !== "string" || !COMMAND_AUDIENCES.has(command["audience"])) {
    p.at(`${at}.audience`, `must be one of ${[...COMMAND_AUDIENCES].join(", ")}`);
  }
  if (typeof command["mutates"] !== "boolean") p.at(`${at}.mutates`, "must be a boolean");
  if (command["guidance"] !== undefined) requireString(p, `${at}.guidance`, command["guidance"]);
  const args = command["arguments"];
  if (!Array.isArray(args)) {
    p.at(`${at}.arguments`, "must be an array, empty when the command takes none");
  } else {
    const seen = new Set<string>();
    args.forEach((arg, index) => {
      checkArgument(p, `${at}.arguments[${index}]`, arg);
      if (isObject(arg) && typeof arg["name"] === "string") {
        if (seen.has(arg["name"])) p.at(`${at}.arguments[${index}].name`, "is declared twice");
        seen.add(arg["name"]);
      }
    });
  }
  return typeof command["name"] === "string" ? command["name"] : undefined;
}

/** $defs/concepts */
function checkConcepts(p: Problems, concepts: unknown): void {
  if (!isObject(concepts)) {
    p.at("data.concepts", "must be an object");
    return;
  }
  const output = concepts["output_contract"];
  if (!isObject(output)) {
    p.at("data.concepts.output_contract", "must be an object");
  } else {
    requireString(p, "data.concepts.output_contract.envelope", output["envelope"]);
    const codes = output["exit_codes"];
    if (!isObject(codes) || Object.keys(codes).length === 0) {
      p.at("data.concepts.output_contract.exit_codes", "must be a non-empty object keyed by code");
    }
  }
  const errors = concepts["error_codes"];
  if (!Array.isArray(errors)) {
    p.at("data.concepts.error_codes", "must be an array");
  } else {
    errors.forEach((entry, index) => {
      const at = `data.concepts.error_codes[${index}]`;
      if (!isObject(entry)) {
        p.at(at, "must be an object");
        return;
      }
      requireString(p, `${at}.code`, entry["code"]);
      requireString(p, `${at}.meaning`, entry["meaning"]);
    });
  }
}

export function validateContract(envelope: unknown): readonly string[] {
  const p = new Problems();
  if (!isObject(envelope)) {
    p.at("$", "must be a JSON object");
    return p.list;
  }
  if (typeof envelope["schema_version"] !== "number") {
    p.at("schema_version", "must be a number");
  }
  if (envelope["ok"] !== true) p.at("ok", "must be true — a guide that failed is not a contract");

  const data = envelope["data"];
  if (!isObject(data)) {
    p.at("data", "must be an object");
    return p.list;
  }
  if (data["contract_version"] !== 1) p.at("data.contract_version", "must be 1");

  const meta = data["meta"];
  let audience: unknown;
  if (!isObject(meta)) {
    p.at("data.meta", "must be an object");
  } else {
    requireString(p, "data.meta.name", meta["name"]);
    requireString(p, "data.meta.version", meta["version"]);
    requireString(p, "data.meta.purpose", meta["purpose"]);
    audience = meta["audience"];
    if (typeof audience !== "string" || !CLI_AUDIENCES.has(audience)) {
      p.at("data.meta.audience", `must be one of ${[...CLI_AUDIENCES].join(", ")}`);
    }
  }

  const commands = data["commands"];
  const names: string[] = [];
  const nonMutating: string[] = [];
  if (!Array.isArray(commands) || commands.length === 0) {
    p.at("data.commands", "must be a non-empty array");
  } else {
    const seen = new Set<string>();
    commands.forEach((command, index) => {
      const name = checkCommand(p, `data.commands[${index}]`, command);
      if (name === undefined) return;
      if (seen.has(name)) p.at(`data.commands[${index}].name`, `duplicates "${name}"`);
      seen.add(name);
      names.push(name);
      if (isObject(command) && command["mutates"] === false) nonMutating.push(name);
    });
  }

  // The conditional branch of $defs/contract: an agent CLI owes the conceptual layer.
  if (audience === "agent") {
    requireString(p, "data.guidance", data["guidance"]);
    if (data["concepts"] === undefined) {
      p.at("data.concepts", "is required when meta.audience is agent");
    } else {
      checkConcepts(p, data["concepts"]);
    }
  }

  // Cross-field agreements JSON Schema cannot state.
  const concepts = data["concepts"];
  if (isObject(concepts) && concepts["read_only_commands"] !== undefined) {
    const declared = concepts["read_only_commands"];
    if (!Array.isArray(declared)) {
      p.at("data.concepts.read_only_commands", "must be an array");
    } else {
      for (const name of declared) {
        if (typeof name !== "string") continue;
        if (!names.includes(name)) {
          p.at("data.concepts.read_only_commands", `names "${name}", which is not a command`);
        } else if (!nonMutating.includes(name)) {
          p.at("data.concepts.read_only_commands", `names "${name}", which declares mutates: true`);
        }
      }
      for (const name of nonMutating) {
        if (!declared.includes(name)) {
          p.at("data.concepts.read_only_commands", `omits "${name}", which declares mutates: false`);
        }
      }
    }
  }
  if (audience === "operator" && Array.isArray(commands)) {
    commands.forEach((command, index) => {
      if (isObject(command) && command["audience"] === "agent") {
        p.at(`data.commands[${index}].audience`, "is agent, but the CLI declares meta.audience operator");
      }
    });
  }

  return p.list;
}

function usage(): never {
  process.stderr.write(
    "Usage: validate-agent-contract.ts <cli-name> | --file <contract.json>\n",
  );
  process.exit(2);
}

function main(argv: readonly string[]): number {
  if (argv.length === 0) usage();

  let raw: string;
  let source: string;
  if (argv[0] === "--file") {
    const path = argv[1];
    if (path === undefined) usage();
    source = path;
    raw = readFileSync(path, "utf8");
  } else {
    const cli = argv[0]!;
    source = `${cli} guide --json`;
    const run = Bun.spawnSync([cli, "guide", "--json"], { stdout: "pipe", stderr: "pipe" });
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
