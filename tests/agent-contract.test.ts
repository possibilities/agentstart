import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { validateContract } from "../scripts/validate-agent-contract.ts";
import { validateAgainstSchema } from "../scripts/json-schema-subset.ts";

const root = resolve(import.meta.dir, "..");
const schemaPath = join(root, "config", "agent-contract", "schema.json");
const schema = JSON.parse(readFileSync(schemaPath, "utf8")) as Record<string, unknown>;

/**
 * One valid agent-audience contract, including a nested command group — the
 * shape AgentWiki's `artifacts list|rm` and AgentBoard's `groom export|apply`
 * actually have. Every rule test mutates a deep clone, so a fixture that stops
 * being valid fails loudly in `accepts the base fixture` rather than quietly
 * weakening the tests built on it.
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
          envelope: { schema_version: "number", ok: "boolean", data: "payload | null" },
          exit_codes: { "0": "success", "1": "runtime failure", "2": "usage fault" },
        },
        error_codes: [{ code: "not_found", meaning: "No such record.", recovery: "Search first." }],
        read_only_commands: ["read", "artifacts list"],
        agent_defaults: ["Call read before answering."],
      },
      global_arguments: [
        { name: "--json", type: "boolean", description: "Emit the envelope", aliases: ["-j"] },
      ],
      commands: [
        {
          name: "read",
          summary: "Read one record",
          audience: "agent",
          mutates: false,
          arguments: [
            { name: "ref", type: "string", description: "Record to read", positional: true, required: true, format: "ref" },
            { name: "--id", type: "string", description: "Exact id instead of a ref" },
          ],
          constraints: [{ kind: "one_of", arguments: ["ref", "--id"], required: true }],
        },
        {
          name: "write",
          summary: "Write one record",
          audience: "agent",
          mutates: true,
          stdin: { accepts: "text", description: "Body, when --body is absent" },
          arguments: [
            { name: "--depth", type: "string", description: "How deep", choices: ["low", "high"], default: "low" },
            { name: "--out", type: "string", description: "Where to write", format: "path", direction: "out" },
          ],
        },
        {
          name: "artifacts",
          summary: "List, inspect, and tombstone artifacts",
          audience: "agent",
          subcommands: [
            { name: "list", summary: "List artifacts", audience: "agent", mutates: false, arguments: [] },
            {
              name: "rm",
              summary: "Tombstone one artifact",
              audience: "agent",
              mutates: true,
              arguments: [
                { name: "name", type: "string", description: "Artifact", positional: true, required: true },
                { name: "--reason", type: "string", description: "Why", required: true },
              ],
            },
          ],
        },
        { name: "serve", summary: "Run the server", audience: "operator", mutates: true, arguments: [] },
      ],
    },
  };
}

const clone = (): Record<string, unknown> => JSON.parse(JSON.stringify(base()));
const data = (f: Record<string, unknown>) => f["data"] as Record<string, unknown>;
const commands = (f: Record<string, unknown>) => data(f)["commands"] as Record<string, unknown>[];
const concepts = (f: Record<string, unknown>) => data(f)["concepts"] as Record<string, unknown>;
const meta = (f: Record<string, unknown>) => data(f)["meta"] as Record<string, unknown>;
const said = (f: Record<string, unknown>) => validateContract(f).join("\n");

describe("the schema is executed, not mirrored", () => {
  test("the validator and the normative schema agree by construction", () => {
    // The validator runs schema.json through the interpreter, so a document
    // the schema rejects cannot pass the validator. This asserts the wiring,
    // which is the thing that regressed before.
    const broken = clone();
    (broken as Record<string, unknown>)["schema_version"] = 1.5;
    expect(validateAgainstSchema(schema, broken).length).toBeGreaterThan(0);
    expect(validateContract(broken).length).toBeGreaterThan(0);
  });

  test("an unsupported schema keyword fails loudly rather than silently passing", () => {
    expect(() => validateAgainstSchema({ patternProperties: {} }, {})).toThrow(/unsupported keyword/);
  });
});

describe("a conformant contract", () => {
  test("accepts the base fixture", () => {
    expect(validateContract(base())).toEqual([]);
  });

  test("accepts an operator CLI with no conceptual layer", () => {
    const f = clone();
    meta(f)["audience"] = "operator";
    delete data(f)["guidance"];
    delete data(f)["concepts"];
    const demote = (list: Record<string, unknown>[]) => {
      for (const c of list) {
        c["audience"] = "operator";
        if (Array.isArray(c["subcommands"])) demote(c["subcommands"] as Record<string, unknown>[]);
      }
    };
    demote(commands(f));
    expect(validateContract(f)).toEqual([]);
  });
});

describe("nested command groups", () => {
  test("a group needs no mutates or arguments of its own", () => {
    const group = commands(base())[2] as Record<string, unknown>;
    expect(group["mutates"]).toBeUndefined();
    expect(validateContract(base())).toEqual([]);
  });

  test("a leaf without mutates is rejected", () => {
    const f = clone();
    const subs = commands(f)[2]!["subcommands"] as Record<string, unknown>[];
    delete subs[0]!["mutates"];
    expect(said(f)).toContain("mutates: is required");
  });

  test("read_only_commands addresses a leaf by its full path", () => {
    // AgentBoard's guide already publishes "groom export" today; a contract
    // that cannot express that would force its first adopter to delete a fact.
    expect(validateContract(base())).toEqual([]);
    const f = clone();
    concepts(f)["read_only_commands"] = ["read"];
    expect(said(f)).toContain('omits "artifacts list"');
  });

  test("a read_only path that is a group, not a leaf, is rejected", () => {
    const f = clone();
    concepts(f)["read_only_commands"] = ["read", "artifacts list", "artifacts"];
    expect(said(f)).toContain('names "artifacts", which is not a command');
  });

  test("duplicate sibling names are rejected", () => {
    const f = clone();
    const subs = commands(f)[2]!["subcommands"] as Record<string, unknown>[];
    subs[1]!["name"] = "list";
    expect(said(f)).toContain("duplicates a sibling command name");
  });

  test("the same leaf name under different parents is fine", () => {
    const f = clone();
    commands(f).push({
      name: "profile",
      summary: "Profiles",
      audience: "agent",
      subcommands: [{ name: "list", summary: "List profiles", audience: "agent", mutates: false, arguments: [] }],
    });
    concepts(f)["read_only_commands"] = ["read", "artifacts list", "profile list"];
    expect(validateContract(f)).toEqual([]);
  });
});

describe("divergences the earlier hand-written validator let through", () => {
  const cases: [string, (f: Record<string, unknown>) => void, RegExp][] = [
    ["a fractional schema_version", (f) => { f["schema_version"] = 1.5; }, /schema_version/],
    ["an unknown key in data", (f) => { data(f)["mcp_tools"] = []; }, /not a field this contract defines/],
    ["an unknown key in meta", (f) => { meta(f)["homepage"] = "x"; }, /not a field this contract defines/],
    ["a non-object concepts.model", (f) => { concepts(f)["model"] = "a string"; }, /model/],
    ["a non-string exit code meaning", (f) => {
      (concepts(f)["output_contract"] as Record<string, unknown>)["exit_codes"] = { "0": 0 };
    }, /exit_codes/],
    ["an unknown key in an error code", (f) => {
      (concepts(f)["error_codes"] as Record<string, unknown>[])[0]!["fix"] = "x";
    }, /not a field this contract defines/],
    ["a non-string agent default", (f) => { concepts(f)["agent_defaults"] = [42]; }, /agent_defaults/],
    ["aliases that are not an array", (f) => {
      (data(f)["global_arguments"] as Record<string, unknown>[])[0]!["aliases"] = "nope";
    }, /aliases/],
    ["a non-string guidance on an operator CLI", (f) => {
      meta(f)["audience"] = "operator";
      delete data(f)["concepts"];
      data(f)["guidance"] = 12345;
    }, /guidance/],
  ];
  for (const [label, mutate, expected] of cases) {
    test(`rejects ${label}`, () => {
      const f = clone();
      mutate(f);
      expect(said(f)).toMatch(expected);
    });
  }
});

describe("channels a caller cannot reach", () => {
  test("rejects stdin required on an agent command", () => {
    const f = clone();
    (commands(f)[1]!["stdin"] as Record<string, unknown>)["required"] = true;
    expect(said(f)).toContain("has no pipe");
  });

  test("allows stdin required on an operator command", () => {
    const f = clone();
    commands(f)[1]!["audience"] = "operator";
    (commands(f)[1]!["stdin"] as Record<string, unknown>)["required"] = true;
    expect(validateContract(f)).toEqual([]);
  });

  test("rejects direction on an argument that is not a path", () => {
    const f = clone();
    const args = commands(f)[1]!["arguments"] as Record<string, unknown>[];
    args[0]!["direction"] = "out";
    expect(said(f)).toContain("direction applies only to format: path");
  });
});

describe("argument relations", () => {
  test("rejects a constraint naming an argument the command lacks", () => {
    const f = clone();
    (commands(f)[0]!["constraints"] as Record<string, unknown>[])[0]!["arguments"] = ["ref", "--ghost"];
    expect(said(f)).toContain('names "--ghost", which this command does not accept');
  });

  test("rejects a constraint kind outside the closed set", () => {
    const f = clone();
    (commands(f)[0]!["constraints"] as Record<string, unknown>[])[0]!["kind"] = "maybe";
    expect(said(f)).toMatch(/kind/);
  });

  test("rejects a constraint over fewer than two arguments", () => {
    const f = clone();
    (commands(f)[0]!["constraints"] as Record<string, unknown>[])[0]!["arguments"] = ["ref"];
    expect(said(f)).toMatch(/arguments/);
  });
});

describe("rules JSON Schema cannot state", () => {
  test("rejects read_only_commands naming a mutating command", () => {
    const f = clone();
    concepts(f)["read_only_commands"] = ["read", "artifacts list", "write"];
    expect(said(f)).toContain('names "write", which declares mutates: true');
  });

  test("rejects an agent command inside an operator CLI", () => {
    const f = clone();
    meta(f)["audience"] = "operator";
    delete data(f)["guidance"];
    delete data(f)["concepts"];
    expect(said(f)).toContain("the CLI declares meta.audience operator");
  });

  test("rejects a positional carrying leading dashes", () => {
    const f = clone();
    (commands(f)[0]!["arguments"] as Record<string, unknown>[])[0]!["name"] = "--ref";
    expect(said(f)).toContain("a positional must not carry leading dashes");
  });

  test("rejects a flag missing its leading dashes", () => {
    const f = clone();
    (commands(f)[1]!["arguments"] as Record<string, unknown>[])[0]!["name"] = "depth";
    expect(said(f)).toContain("a flag must carry its leading dashes");
  });

  test("rejects a global flag missing its leading dashes", () => {
    const f = clone();
    (data(f)["global_arguments"] as Record<string, unknown>[])[0]!["name"] = "json";
    expect(said(f)).toContain("a flag must carry its leading dashes");
  });

  test("rejects an argument declared twice", () => {
    const f = clone();
    (commands(f)[0]!["arguments"] as Record<string, unknown>[]).push({
      name: "--id", type: "string", description: "again",
    });
    expect(said(f)).toContain('declares "--id" twice');
  });

  test("rejects an envelope reporting failure", () => {
    const f = clone();
    f["ok"] = false;
    expect(said(f)).toMatch(/ok/);
  });

  test("rejects an agent CLI with no guidance", () => {
    const f = clone();
    delete data(f)["guidance"];
    expect(said(f)).toContain("guidance: is required");
  });

  test("rejects an agent CLI with no concepts", () => {
    const f = clone();
    delete data(f)["concepts"];
    expect(said(f)).toContain("concepts: is required");
  });
});
