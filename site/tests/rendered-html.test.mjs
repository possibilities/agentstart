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
  assert.ok(snapshot.stats.skills > 0);
  assert.equal(snapshot.files.length, snapshot.stats.files);
  assert.equal(
    snapshot.files.filter((file) => /^skills\/[^/]+\/SKILL\.md$/.test(file.path)).length,
    snapshot.stats.skills,
    "every reported skill should have one root manifest",
  );
  assert.equal(
    new Set(snapshot.files.map((file) => file.path)).size,
    snapshot.files.length,
    "every snapshot path should be unique",
  );
  assert.ok(snapshot.files.some((file) => file.path === "capability.json"));
  assert.ok(snapshot.files.some((file) => file.path === "guidance/AGENTS.md"));
  assert.ok(snapshot.files.some((file) => file.path.endsWith("/SKILL.md")));
});

test("keeps the resource explorer reachable within the viewport", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

  assert.match(css, /\.explorer-shell\s*\{[^}]*height:\s*100dvh;/s);
  assert.match(css, /\.file-pane\s*\{[^}]*min-height:\s*0;[^}]*overflow:\s*hidden;/s);
  assert.match(css, /\.file-list\s*\{[^}]*min-height:\s*0;[^}]*overflow-y:\s*auto;/s);
  assert.match(css, /\.document-pane\s*\{[^}]*min-height:\s*0;[^}]*overflow-y:\s*auto;/s);
});

test("follows the system color scheme without a stored override", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");

  assert.match(css, /@media\s*\(prefers-color-scheme:\s*dark\)/);
  assert.match(css, /@media\s*\(prefers-color-scheme:\s*dark\)[^{]*\{\s*:root\s*\{[^}]*color-scheme:\s*dark;/s);
  assert.doesNotMatch(css, /data-theme|theme-toggle|localStorage/);
});
