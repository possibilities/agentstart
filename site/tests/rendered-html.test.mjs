import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
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

test("server-renders the Common Pack atlas", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Common Pack — AgentStart capability atlas<\/title>/i);
  assert.match(html, /One field manual\./);
  assert.match(html, /Three native dialects\./);
  assert.match(html, /Browse every file/);
  assert.match(html, /Reading the common pack/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape|Building your site/i);
});

test("checks in a complete, internally consistent pack snapshot", async () => {
  const source = await readFile(
    new URL("../public/common-pack.json", import.meta.url),
    "utf8",
  );
  const snapshot = JSON.parse(source);

  assert.equal(snapshot.schemaVersion, 1);
  assert.equal(snapshot.id, "common");
  assert.equal(snapshot.stats.skills, 34);
  assert.equal(snapshot.stats.files, 290);
  assert.equal(snapshot.files.length, snapshot.stats.files);
  assert.equal(
    new Set(snapshot.files.map((file) => file.path)).size,
    snapshot.files.length,
    "every snapshot path should be unique",
  );
  assert.ok(snapshot.files.some((file) => file.path === "capability.json"));
  assert.ok(snapshot.files.some((file) => file.path === "guidance/AGENTS.md"));
  assert.ok(snapshot.files.some((file) => file.path.endsWith("/SKILL.md")));
});
