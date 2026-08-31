import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { validateContract } from "../scripts/validate-agent-contract.ts";

const root = resolve(import.meta.dir, "..");
const schemaPath = join(root, "config", "agent-contract", "schema.json");

/**
 * One valid agent-audience contract. Every rule test mutates a deep clone of
 * this, so a fixture that stops being valid fails loudly in `accepts the base
 * fixture` rather than silently weakening the rule tests that build on it.
 */
function base(): Record<string, unknown> {
  return {
    schema_version: 1,
    ok: true,
    error: null,
    data: {
      contract_version: 1,
      meta: {
        name: "agentexample",
        version: "0.1.0",
        purpose: "Demonstrate the contract in a fixture.",
        audience: "agent",
      },
      guidance: "Reach for read before write.",
      concepts: {
        output_contract: {
          envelope: "{schema_version, ok, error, data}",
          exit_codes: { "0": "success", "1": "runtime failure", "2": "usage fault" },
        },
        error_codes: [{ code: "not_found", meaning: "No such record.", recovery: "Search first." }],
        read_only_commands: ["read"],
        agent_defaults: ["Call read before answering."],
      },
      commands: [
        {
          name: "read",
          summary: "Read one record",
          audience: "agent",
          mutates: false,
          arguments: [
            { name: "ref", type: "string", description: "Record to read", positional: true, required: true, format: "ref" },
            { name: "--json", type: "boolean", description: "Emit the envelope", aliases: ["-j"] },
          ],
        },
        {
          name: "write",
          summary: "Write one record",
          audience: "agent",
          mutates: true,
          arguments: [
            { name: "--depth", type: "string", description: "How deep", choices: ["low", "high"], default: "low" },
          ],
        },
        { name: "serve", summary: "Run the server", audience: "operator", mutates: true, arguments: [] },
      ],
    },
  };
}

function clone(): Record<string, unknown> {
  return JSON.parse(JSON.stringify(base()));
}

/** Reach into the fixture without `any` noise at every call site. */
function data(fixture: Record<string, unknown>): Record<string, unknown> {
  return fixture["data"] as Record<string, unknown>;
}
function commands(fixture: Record<string, unknown>): Record<string, unknown>[] {
  return data(fixture)["commands"] as Record<string, unknown>[];
}
function concepts(fixture: Record<string, unknown>): Record<string, unknown> {
  return data(fixture)["concepts"] as Record<string, unknown>;
}

describe("the published schema", () => {
  test("is parseable and declares the definitions the validator mirrors", () => {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as Record<string, unknown>;
    const defs = schema["$defs"] as Record<string, unknown>;
    expect(Object.keys(defs).sort()).toEqual(["argument", "command", "concepts", "contract", "meta"]);
  });
});

describe("a conformant contract", () => {
  test("accepts the base fixture", () => {
    expect(validateContract(base())).toEqual([]);
  });

  test("accepts an operator CLI with no conceptual layer", () => {
    const fixture = clone();
    (data(fixture)["meta"] as Record<string, unknown>)["audience"] = "operator";
    delete data(fixture)["guidance"];
    delete data(fixture)["concepts"];
    for (const command of commands(fixture)) command["audience"] = "operator";
    expect(validateContract(fixture)).toEqual([]);
  });
});

describe("rules the schema states", () => {
  test("rejects a contract_version that is not 1", () => {
    const fixture = clone();
    data(fixture)["contract_version"] = 2;
    expect(validateContract(fixture)).toContain("data.contract_version: must be 1");
  });

  test("rejects an unknown CLI audience", () => {
    const fixture = clone();
    (data(fixture)["meta"] as Record<string, unknown>)["audience"] = "robot";
    expect(validateContract(fixture).join("\n")).toContain("data.meta.audience");
  });

  test("rejects an unknown command audience", () => {
    const fixture = clone();
    commands(fixture)[0]!["audience"] = "everyone";
    expect(validateContract(fixture).join("\n")).toContain("data.commands[0].audience");
  });

  test("rejects a non-scalar argument type", () => {
    const fixture = clone();
    (commands(fixture)[0]!["arguments"] as Record<string, unknown>[])[0]!["type"] = "object";
    expect(validateContract(fixture).join("\n")).toContain("data.commands[0].arguments[0].type");
  });

  test("rejects an unknown format", () => {
    const fixture = clone();
    (commands(fixture)[0]!["arguments"] as Record<string, unknown>[])[0]!["format"] = "slug";
    expect(validateContract(fixture).join("\n")).toContain("arguments[0].format");
  });

  test("rejects a field the contract does not define", () => {
    const fixture = clone();
    commands(fixture)[0]!["mcp_tool"] = "read_record";
    expect(validateContract(fixture).join("\n")).toContain("is not a contract field");
  });

  test("rejects a missing mutates flag", () => {
    const fixture = clone();
    delete commands(fixture)[0]!["mutates"];
    expect(validateContract(fixture)).toContain("data.commands[0].mutates: must be a boolean");
  });

  test("rejects a duplicate command name", () => {
    const fixture = clone();
    commands(fixture)[1]!["name"] = "read";
    expect(validateContract(fixture).join("\n")).toContain('duplicates "read"');
  });

  test("rejects an empty command list", () => {
    const fixture = clone();
    data(fixture)["commands"] = [];
    expect(validateContract(fixture)).toContain("data.commands: must be a non-empty array");
  });

  test("rejects an agent CLI with no guidance", () => {
    const fixture = clone();
    delete data(fixture)["guidance"];
    expect(validateContract(fixture)).toContain("data.guidance: must be a non-empty string");
  });

  test("rejects an agent CLI with no concepts", () => {
    const fixture = clone();
    delete data(fixture)["concepts"];
    expect(validateContract(fixture)).toContain("data.concepts: is required when meta.audience is agent");
  });

  test("rejects concepts with no exit codes", () => {
    const fixture = clone();
    (concepts(fixture)["output_contract"] as Record<string, unknown>)["exit_codes"] = {};
    expect(validateContract(fixture).join("\n")).toContain("exit_codes");
  });

  test("rejects an error code entry with no meaning", () => {
    const fixture = clone();
    (concepts(fixture)["error_codes"] as Record<string, unknown>[])[0] = { code: "bare" };
    expect(validateContract(fixture).join("\n")).toContain("error_codes[0].meaning");
  });
});

describe("rules JSON Schema cannot state", () => {
  test("rejects read_only_commands that omits a non-mutating command", () => {
    const fixture = clone();
    concepts(fixture)["read_only_commands"] = [];
    expect(validateContract(fixture).join("\n")).toContain('omits "read"');
  });

  test("rejects read_only_commands that names a mutating command", () => {
    const fixture = clone();
    concepts(fixture)["read_only_commands"] = ["read", "write"];
    expect(validateContract(fixture).join("\n")).toContain('names "write", which declares mutates: true');
  });

  test("rejects read_only_commands that names a command that does not exist", () => {
    const fixture = clone();
    concepts(fixture)["read_only_commands"] = ["read", "ghost"];
    expect(validateContract(fixture).join("\n")).toContain('names "ghost", which is not a command');
  });

  test("rejects an agent command inside an operator CLI", () => {
    const fixture = clone();
    (data(fixture)["meta"] as Record<string, unknown>)["audience"] = "operator";
    delete data(fixture)["guidance"];
    delete data(fixture)["concepts"];
    expect(validateContract(fixture).join("\n")).toContain("the CLI declares meta.audience operator");
  });

  test("rejects a positional carrying leading dashes", () => {
    const fixture = clone();
    (commands(fixture)[0]!["arguments"] as Record<string, unknown>[])[0]!["name"] = "--ref";
    expect(validateContract(fixture).join("\n")).toContain("a positional must not carry leading dashes");
  });

  test("rejects a flag missing its leading dashes", () => {
    const fixture = clone();
    (commands(fixture)[1]!["arguments"] as Record<string, unknown>[])[0]!["name"] = "depth";
    expect(validateContract(fixture).join("\n")).toContain("a flag must carry its leading dashes");
  });

  test("rejects an argument declared twice", () => {
    const fixture = clone();
    const args = commands(fixture)[0]!["arguments"] as Record<string, unknown>[];
    args.push({ name: "--json", type: "boolean", description: "again" });
    expect(validateContract(fixture).join("\n")).toContain("is declared twice");
  });

  test("rejects an envelope reporting failure", () => {
    const fixture = clone();
    fixture["ok"] = false;
    expect(validateContract(fixture).join("\n")).toContain("a guide that failed is not a contract");
  });
});
