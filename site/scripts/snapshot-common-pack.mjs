import { createHash } from "node:crypto";
import { access, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = fileURLToPath(new URL("..", import.meta.url));
const dataHome = process.env.XDG_DATA_HOME || join(homedir(), ".local", "share");
const capabilitiesRoot =
  process.env.AGENTSTART_CAPABILITIES_ROOT || join(dataHome, "agentstart", "capabilities");
const packRoot = join(capabilitiesRoot, "packs", "common");
const outputPath = join(siteRoot, "public", "common-pack.json");

const imageTypes = new Map([
  [".png", "image/png"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".gif", "image/gif"],
  [".webp", "image/webp"],
]);

const languageByExtension = new Map([
  [".md", "markdown"],
  [".json", "json"],
  [".yaml", "yaml"],
  [".yml", "yaml"],
  [".ts", "typescript"],
  [".tsx", "tsx"],
  [".js", "javascript"],
  [".mjs", "javascript"],
  [".sh", "shell"],
  [".txt", "text"],
]);

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name);
      return entry.isDirectory() ? walk(path) : [path];
    }),
  );
  return nested.flat().sort();
}

function stripQuotes(value) {
  const trimmed = value.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return trimmed.slice(1, -1);
    }
  }
  if (trimmed.startsWith("'") && trimmed.endsWith("'")) {
    return trimmed.slice(1, -1).replaceAll("''", "'");
  }
  return trimmed;
}

function frontmatterValue(content, key) {
  if (!content.startsWith("---\n")) return null;
  const end = content.indexOf("\n---", 4);
  if (end < 0) return null;
  const match = content.slice(4, end).match(new RegExp(`^${key}:\\s*(.+)$`, "m"));
  return match ? stripQuotes(match[1]) : null;
}

function heading(content, fallback) {
  const match = content.match(/^#\s+(.+)$/m);
  return match ? match[1].replaceAll("`", "") : fallback;
}

function classify(path) {
  if (path === "capability.json") return "manifest";
  if (path.startsWith("guidance/")) return "guidance";
  if (path.startsWith("pi/")) return "pi";
  if (/^skills\/[^/]+\/SKILL\.md$/.test(path)) return "skill";
  return "support";
}

function skillFor(path) {
  const match = path.match(/^skills\/([^/]+)\//);
  return match ? match[1] : null;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function snapshotFile(absolutePath) {
  const path = relative(packRoot, absolutePath).split("\\").join("/");
  const extension = extname(path).toLowerCase();
  const metadata = await stat(absolutePath);
  const mime = imageTypes.get(extension) || "text/plain; charset=utf-8";
  const encoding = imageTypes.has(extension) ? "base64" : "utf8";
  const content = await readFile(absolutePath, encoding);
  const text = encoding === "utf8" ? content : "";
  const fallbackTitle = basename(path);

  return {
    path,
    title: heading(text, fallbackTitle),
    description: frontmatterValue(text, "description"),
    skill: skillFor(path),
    kind: classify(path),
    language: imageTypes.has(extension)
      ? "image"
      : languageByExtension.get(extension) || "text",
    mime,
    encoding,
    size: metadata.size,
    hash: sha256(content),
    content,
  };
}

if (!(await exists(packRoot))) {
  if (await exists(outputPath)) {
    console.log(`Common pack unavailable at ${packRoot}; keeping the checked-in snapshot.`);
    process.exit(0);
  }
  throw new Error(`Common capability pack not found at ${packRoot}`);
}

const absoluteFiles = await walk(packRoot);
const files = await Promise.all(absoluteFiles.map(snapshotFile));
const manifestFile = files.find((file) => file.path === "capability.json");
const manifest = manifestFile ? JSON.parse(manifestFile.content) : {};
const digest = sha256(files.map((file) => `${file.path}\0${file.hash}`).join("\n")).slice(0, 24);
const snapshot = {
  schemaVersion: 1,
  id: manifest.id || "common",
  description: manifest.description || "AgentStart's default capability pack",
  digest,
  stats: {
    skills: files.filter((file) => file.kind === "skill").length,
    files: files.length,
    bytes: files.reduce((total, file) => total + file.size, 0),
    guidance: files.filter((file) => file.kind === "guidance").length,
    piResources: files.filter((file) => file.kind === "pi").length,
  },
  files,
};

await mkdir(join(siteRoot, "public"), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(snapshot)}\n`);
console.log(
  `Snapshotted ${snapshot.stats.skills} skills and ${snapshot.stats.files} files from common (${digest}).`,
);
