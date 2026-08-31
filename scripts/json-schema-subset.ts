#!/usr/bin/env bun

/**
 * A deliberately small JSON Schema (draft 2020-12) interpreter.
 *
 * AgentStart carries no package.json, so it cannot reach for ajv — but the
 * alternative it reached for first was worse: a hand-written validator that
 * *mirrored* config/agent-contract/schema.json and drifted from it in nine
 * places, in both directions, while the README claimed the schema was
 * normative. Two authorships of one set of rules is the exact disease the
 * agent contract exists to cure, so curing it here is not optional.
 *
 * This interprets the schema instead. Everything the contract document
 * actually uses is supported and nothing else is: unsupported keywords are a
 * loud error, never a silent pass, so a schema edit that outgrows this file
 * fails immediately rather than quietly stopping being enforced.
 */

const SUPPORTED = new Set([
  "$schema", "$id", "$ref", "$defs", "title", "description", "default",
  "type", "const", "enum", "properties", "required", "additionalProperties",
  "items", "minItems", "minLength", "minimum", "maximum",
  "allOf", "if", "then", "not", "patternProperties",
]);

type Json = unknown;
type Schema = Record<string, Json>;

export interface Violation {
  path: string;
  message: string;
}

function typeOf(value: Json): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (Number.isInteger(value)) return "integer";
  return typeof value;
}

/** draft 2020-12: an integer instance also satisfies "number". */
function matchesType(value: Json, expected: string): boolean {
  const actual = typeOf(value);
  if (expected === "number") return actual === "number" || actual === "integer";
  if (expected === "object") return actual === "object";
  return actual === expected;
}

function resolveRef(root: Schema, ref: string): Schema {
  if (!ref.startsWith("#/")) throw new Error(`unsupported $ref form: ${ref}`);
  let node: Json = root;
  for (const rawSegment of ref.slice(2).split("/")) {
    const segment = rawSegment.replace(/~1/g, "/").replace(/~0/g, "~");
    if (typeof node !== "object" || node === null) {
      throw new Error(`$ref ${ref} does not resolve`);
    }
    node = (node as Record<string, Json>)[segment];
  }
  if (typeof node !== "object" || node === null) throw new Error(`$ref ${ref} does not resolve`);
  return node as Schema;
}

function assertSupported(schema: Schema, at: string): void {
  for (const keyword of Object.keys(schema)) {
    if (!SUPPORTED.has(keyword)) {
      throw new Error(
        `schema uses unsupported keyword "${keyword}" at ${at}; ` +
          "teach scripts/json-schema-subset.ts before using it",
      );
    }
  }
}

function check(root: Schema, schema: Schema, value: Json, path: string, out: Violation[]): void {
  assertSupported(schema, path || "$");

  if (typeof schema["$ref"] === "string") {
    check(root, resolveRef(root, schema["$ref"]), value, path, out);
    return;
  }

  if (schema["const"] !== undefined && JSON.stringify(value) !== JSON.stringify(schema["const"])) {
    out.push({ path, message: `must be ${JSON.stringify(schema["const"])}` });
    return;
  }

  if (Array.isArray(schema["enum"])) {
    const allowed = schema["enum"] as Json[];
    if (!allowed.some((option) => JSON.stringify(option) === JSON.stringify(value))) {
      out.push({ path, message: `must be one of ${allowed.map((o) => String(o)).join(", ")}` });
      return;
    }
  }

  const type = schema["type"];
  if (typeof type === "string" && !matchesType(value, type)) {
    out.push({ path, message: `must be ${type}, got ${typeOf(value)}` });
    return;
  }

  if (typeof schema["minLength"] === "number" && typeof value === "string") {
    if (value.length < schema["minLength"]) {
      out.push({ path, message: `must not be empty` });
    }
  }

  if (typeof value === "number") {
    if (typeof schema["minimum"] === "number" && value < schema["minimum"]) {
      out.push({ path, message: `must be at least ${schema["minimum"]}` });
    }
    if (typeof schema["maximum"] === "number" && value > schema["maximum"]) {
      out.push({ path, message: `must be at most ${schema["maximum"]}` });
    }
  }

  if (Array.isArray(value)) {
    if (typeof schema["minItems"] === "number" && value.length < schema["minItems"]) {
      out.push({ path, message: `must have at least ${schema["minItems"]} item(s)` });
    }
    const items = schema["items"];
    if (items !== undefined) {
      value.forEach((entry, index) => {
        check(root, items as Schema, entry, `${path}[${index}]`, out);
      });
    }
  }

  if (typeOf(value) === "object") {
    const object = value as Record<string, Json>;
    const properties = (schema["properties"] as Record<string, Schema> | undefined) ?? undefined;

    if (Array.isArray(schema["required"])) {
      for (const key of schema["required"] as string[]) {
        if (!(key in object)) {
          out.push({ path: path === "" ? key : `${path}.${key}`, message: "is required" });
        }
      }
    }

    if (properties !== undefined) {
      for (const [key, sub] of Object.entries(properties)) {
        if (key in object) {
          check(root, sub, object[key], path === "" ? key : `${path}.${key}`, out);
        }
      }
    }

    // patternProperties is how the contract keeps `additionalProperties: false`
    // strict while still admitting `x_` extensions — a closed shape plus a
    // frozen version number would otherwise make version 2 a fifteen-repository
    // flag day.
    const patterns = schema["patternProperties"] as Record<string, Schema> | undefined;
    if (patterns !== undefined) {
      for (const [pattern, sub] of Object.entries(patterns)) {
        const re = new RegExp(pattern);
        for (const [key, entry] of Object.entries(value as Record<string, Json>)) {
          if (re.test(key)) check(root, sub, entry, path === "" ? key : `${path}.${key}`, out);
        }
      }
    }

    const additional = schema["additionalProperties"];
    if (additional !== undefined && additional !== true) {
      const known = new Set(Object.keys(properties ?? {}));
      const patternList = Object.keys(patterns ?? {}).map((p) => new RegExp(p));
      for (const key of Object.keys(object)) {
        if (known.has(key)) continue;
        if (patternList.some((re) => re.test(key))) continue;
        const where = path === "" ? key : `${path}.${key}`;
        if (additional === false) {
          out.push({ path: where, message: "is not a field this contract defines" });
        } else {
          check(root, additional as Schema, object[key], where, out);
        }
      }
    }
  }

  if (Array.isArray(schema["allOf"])) {
    for (const sub of schema["allOf"] as Schema[]) {
      check(root, sub, value, path, out);
    }
  }

  if (schema["not"] !== undefined) {
    const probe: Violation[] = [];
    check(root, schema["not"] as Schema, value, path, probe);
    if (probe.length === 0) out.push({ path, message: "must not match the forbidden shape" });
  }

  // if/then only — the contract never needs `else`, and leaving it unsupported
  // means a schema that grows one fails loudly instead of half-applying.
  if (schema["if"] !== undefined) {
    const probe: Violation[] = [];
    check(root, schema["if"] as Schema, value, path, probe);
    if (probe.length === 0 && schema["then"] !== undefined) {
      check(root, schema["then"] as Schema, value, path, out);
    }
  }
}

/** Validate `value` against `root`, returning every violation. */
export function validateAgainstSchema(root: Schema, value: Json): Violation[] {
  const out: Violation[] = [];
  check(root, root, value, "", out);
  return out;
}
