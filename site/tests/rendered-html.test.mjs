import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Fleet Resources field guide", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Fleet Resources — AgentStart advice field guide<\/title>/i);
  assert.match(html, /Your agents arrive/);
  assert.match(html, /with a field guide\./);
  assert.match(html, /Find the right playbook/);
  assert.match(html, /Opening the fleet resource field guide/);
  assert.doesNotMatch(html, /<footer\b|Generated from the installed pack/i);
  assert.doesNotMatch(html, /Browse every file|codex-preview|Your site is taking shape|Building your site/i);
});

test("checks in a complete, advice-focused resource snapshot", async () => {
  const source = await readFile(
    new URL("../public/fleet-resources.json", import.meta.url),
    "utf8",
  );
  const snapshot = JSON.parse(source);

  assert.equal(snapshot.schemaVersion, 2);
  assert.equal(snapshot.id, "fleet-resources");
  assert.equal(snapshot.skills.length, snapshot.stats.skills);
  assert.equal(snapshot.utilities.length, snapshot.stats.utilities);
  assert.equal(snapshot.guidance.length, snapshot.stats.guidance);
  assert.equal(
    snapshot.skills.reduce((total, skill) => total + skill.references.length, 0),
    snapshot.stats.references,
  );
  assert.equal(
    new Set(snapshot.skills.map((skill) => skill.id)).size,
    snapshot.skills.length,
    "every advice skill should be unique",
  );
  assert.ok(snapshot.skills.every((skill) => skill.description.length > 20));
  assert.ok(snapshot.skills.every((skill) => !/^[>|][+-]?$/.test(skill.description)));
  assert.ok(snapshot.skills.every((skill) => snapshot.categories.some((category) => category.id === skill.category)));
  assert.ok(snapshot.startingSkills.every((id) => snapshot.skills.some((skill) => skill.id === id)));
  assert.ok(snapshot.guidance.some((item) => item.id === "guidance/AGENTS.md"));
  assert.equal(snapshot.skills.find((skill) => skill.id === "collab")?.dialects.codex, "$agent:collab");
  assert.equal(snapshot.skills.find((skill) => skill.id === "collab")?.dialects.claude, "/agent:collab");
  assert.deepEqual(
    Object.keys(snapshot.skills.find((skill) => skill.id === "collab")?.dialects ?? {}).sort(),
    ["claude", "codex"],
  );
  assert.equal(snapshot.utilities.length, 0);
  assert.doesNotMatch(
    source,
    /(^|[^A-Za-z0-9_])pi([^A-Za-z0-9_]|$)/i,
    "the public snapshot should not re-advertise a retired harness from vendor prose",
  );
  assert.equal(snapshot.files, undefined, "raw implementation inventory should not ship to the browser");
  assert.ok(snapshot.stats.implementationFiles > snapshot.stats.adviceDocuments);
  assert.ok(Buffer.byteLength(source) < 2_000_000, "the advice guide should stay far smaller than the raw resources");
});

test("refuses retired Pi connector spellings before writing a snapshot", async (t) => {
  const fixture = await mkdtemp(join(tmpdir(), "agentstart-retired-harness-"));
  t.after(() => rm(fixture, { force: true, recursive: true }));
  const resources = join(fixture, "resources");
  const output = join(fixture, "fleet-resources.json");
  await mkdir(join(resources, "skills", "fixture"), { recursive: true });
  await writeFile(
    join(resources, "skills", "fixture", "SKILL.md"),
    "---\nname: fixture\ndescription: A pi_agent connector remnant.\n---\n\n# Fixture\n",
  );

  const result = spawnSync(process.execPath, ["scripts/snapshot-fleet-resources.mjs"], {
    cwd: new URL("..", import.meta.url),
    env: {
      ...process.env,
      AGENTSTART_RESOURCES_ROOT: resources,
      AGENTSTART_SNAPSHOT_OUTPUT: output,
    },
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /retired Pi spelling/);
  await assert.rejects(readFile(output), { code: "ENOENT" });
});

test("keeps the advice guide reachable within the viewport", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

  assert.match(css, /\.guide-shell\s*\{[^}]*height:\s*100dvh;/s);
  assert.match(css, /\.guide-nav\s*\{[^}]*min-height:\s*0;[^}]*overflow:\s*hidden;/s);
  assert.match(css, /\.skill-list\s*\{[^}]*min-height:\s*0;[^}]*overflow-y:\s*auto;/s);
  assert.match(css, /\.guide-reader\s*\{[^}]*min-height:\s*0;[^}]*overflow-y:\s*auto;/s);
});

test("keeps the field guide comfortable to read", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

  assert.match(css, /\.intent-search input\s*\{[^}]*font-size:\s*16px;/s);
  assert.match(css, /\.skill-list\s*>\s*button p\s*\{[^}]*font-size:\s*14px;/s);
  assert.match(css, /\.skill-list\s*>\s*button strong\s*\{[^}]*font-size:\s*20px;/s);
  assert.match(css, /\.advice-markdown\s*\{[^}]*font-size:\s*18px;/s);
  assert.match(css, /\.advice-markdown table\s*\{[^}]*font-size:\s*14px;/s);
});

test("follows the system color scheme without a stored override", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

  assert.match(css, /@media\s*\(prefers-color-scheme:\s*dark\)/);
  assert.match(css, /@media\s*\(prefers-color-scheme:\s*dark\)[^{]*\{\s*:root\s*\{[^}]*color-scheme:\s*dark;/s);
  assert.doesNotMatch(css, /data-theme|theme-toggle|localStorage/);
});
