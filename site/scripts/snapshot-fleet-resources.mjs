import { createHash } from "node:crypto";
import { access, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = fileURLToPath(new URL("..", import.meta.url));
const dataHome = process.env.XDG_DATA_HOME || join(homedir(), ".local", "share");
const resourcesRoot =
  process.env.AGENTSTART_RESOURCES_ROOT || join(dataHome, "agentstart", "resources");
const outputPath =
  process.env.AGENTSTART_SNAPSHOT_OUTPUT || join(siteRoot, "public", "fleet-resources.json");

const retiredPiSpelling =
  /(^|[^A-Za-z0-9_])pi([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])pi_(?:agent|coding_agent|session|subagents|viewer)([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])pi(?:Agent|CodingAgent|Session|Subagents|Viewer)([^A-Za-z0-9_]|$)/i;

const categoryCatalog = [
  {
    id: "work",
    label: "Shape and run work",
    description: "Turn an idea into the right kind of collaboration, plan, or autonomous run.",
    skills: ["collab", "prompt", "build", "orchestrate", "board", "groom", "story"],
  },
  {
    id: "knowledge",
    label: "Find and preserve knowledge",
    description: "Research the web and local archives, then keep conclusions somewhere durable.",
    skills: ["brain", "chats", "search", "scrape", "wiki", "resource-create", "resource-update"],
  },
  {
    id: "operate",
    label: "Operate tools and interfaces",
    description: "Work through browsers, native apps, terminals, messages, and the live agent surface.",
    skills: [
      "browser",
      "desktop",
      "terminal-control",
      "email",
      "notify",
      "keys",
      "herdr",
      "bus",
      "hunk-review",
    ],
  },
  {
    id: "products",
    label: "Build better products",
    description: "Apply focused craft for AI interfaces, native apps, React, components, and visual design.",
    skills: [
      "ai-elements",
      "ai-sdk",
      "frontend-design",
      "shadcn",
      "vercel-react-best-practices",
      "web-design-guidelines",
      "native-sdk",
    ],
  },
  {
    id: "system",
    label: "Extend and maintain the system",
    description: "Discover new capabilities and keep the fleet, forks, and upstream work healthy.",
    skills: ["find-skills", "fleet", "maintain", "supervise", "watch-requests"],
  },
];

const displayNames = {
  "ai-elements": "AI Elements",
  "ai-sdk": "AI SDK",
  board: "Board",
  brain: "Brain",
  browser: "Browser",
  build: "Build",
  bus: "Agent Bus",
  chats: "Past Chats",
  collab: "Collaborate",
  desktop: "Desktop",
  email: "Email and Calendar",
  "find-skills": "Find Skills",
  fleet: "Fleet Map",
  "frontend-design": "Frontend Design",
  groom: "Groom the Plan",
  herdr: "Herdr",
  "hunk-review": "Hunk Review",
  keys: "Keyboard Shortcuts",
  maintain: "Maintain a Fork",
  "native-sdk": "Native SDK",
  notify: "Notify",
  orchestrate: "Orchestrate",
  prompt: "Write an Agent Prompt",
  "resource-create": "Create a Research Resource",
  "resource-update": "Update a Research Resource",
  scrape: "Fetch a URL",
  search: "Search the Web",
  shadcn: "shadcn/ui",
  story: "Explain a Codebase",
  supervise: "Supervisor",
  "terminal-control": "Terminal Control",
  "vercel-react-best-practices": "React Best Practices",
  "watch-requests": "Watch Pull Requests",
  "web-design-guidelines": "Review a Web Interface",
  wiki: "Durable Wiki",
};

const utilityCatalog = [];

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

function foldYamlLines(lines) {
  const paragraphs = [];
  let current = [];
  for (const line of lines) {
    const text = line.trim();
    if (text === "") {
      if (current.length > 0) paragraphs.push(current.join(" "));
      current = [];
    } else {
      current.push(text);
    }
  }
  if (current.length > 0) paragraphs.push(current.join(" "));
  return paragraphs.join("\n\n");
}

function frontmatter(content) {
  if (!content.startsWith("---\n")) return { attributes: {}, body: content };
  const end = content.indexOf("\n---", 4);
  if (end < 0) return { attributes: {}, body: content };

  const lines = content.slice(4, end).split("\n");
  const attributes = {};
  for (let index = 0; index < lines.length; index += 1) {
    const match = lines[index].match(/^([A-Za-z0-9_-]+):(?:\s*(.*))?$/);
    if (!match) continue;
    const [, key, rawValue = ""] = match;
    if (/^[>|][+-]?$/.test(rawValue)) {
      const block = [];
      while (index + 1 < lines.length && /^(\s+|$)/.test(lines[index + 1])) {
        index += 1;
        block.push(lines[index]);
      }
      attributes[key] = rawValue.startsWith(">")
        ? foldYamlLines(block)
        : block.map((line) => line.replace(/^\s+/, "")).join("\n");
    } else {
      attributes[key] = stripQuotes(rawValue);
    }
  }

  return {
    attributes,
    body: content.slice(end + 4).replace(/^\s+/, ""),
  };
}

function heading(content, fallback) {
  const match = content.match(/^#\s+(.+)$/m);
  return match ? match[1].replaceAll("`", "") : fallback;
}

function shortSummary(description) {
  const firstSentence = description.match(/^(.+?[.!?])(?:\s|$)/)?.[1] || description;
  if (firstSentence.length <= 220) return firstSentence;
  const clipped = firstSentence.slice(0, 217).replace(/\s+\S*$/, "");
  return `${clipped}…`;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function categoryFor(skillId) {
  return categoryCatalog.find((category) => category.skills.includes(skillId))?.id || "system";
}

if (!(await exists(resourcesRoot))) {
  if (await exists(outputPath)) {
    console.log(`Fleet resources unavailable at ${resourcesRoot}; keeping the checked-in snapshot.`);
    process.exit(0);
  }
  throw new Error(`AgentStart fleet resources not found at ${resourcesRoot}`);
}

const absoluteFiles = await walk(resourcesRoot);
const inventory = await Promise.all(
  absoluteFiles.map(async (absolutePath) => {
    const path = relative(resourcesRoot, absolutePath).split("\\").join("/");
    const content = await readFile(absolutePath);
    return { absolutePath, path, hash: sha256(content) };
  }),
);

const skillIds = inventory
  .map((file) => file.path.match(/^skills\/([^/]+)\/SKILL\.md$/)?.[1])
  .filter(Boolean)
  .sort();

const skills = await Promise.all(
  skillIds.map(async (id) => {
    const manifestPath = join(resourcesRoot, "skills", id, "SKILL.md");
    const manifestSource = await readFile(manifestPath, "utf8");
    const parsed = frontmatter(manifestSource);
    const description = parsed.attributes.description || `Advice for using ${displayNames[id] || id}.`;
    const referenceFiles = inventory.filter(
      (file) =>
        file.path.startsWith(`skills/${id}/`) &&
        file.path !== `skills/${id}/SKILL.md` &&
        file.path.toLowerCase().endsWith(".md"),
    );
    const references = await Promise.all(
      referenceFiles.map(async (file) => {
        const source = await readFile(file.absolutePath, "utf8");
        const reference = frontmatter(source);
        return {
          id: file.path,
          title: heading(reference.body, basename(file.path, ".md")),
          content: reference.body,
        };
      }),
    );

    return {
      id,
      title: displayNames[id] || heading(parsed.body, id),
      category: categoryFor(id),
      summary: shortSummary(description),
      description,
      content: parsed.body,
      references,
      dialects: {
        claude: `/agent:${id}`,
        codex: `$agent:${id}`,
      },
    };
  }),
);

const guidanceFiles = inventory.filter((file) => /^guidance\/.*\.md$/i.test(file.path));
const guidance = await Promise.all(
  guidanceFiles.map(async (file) => {
    const source = await readFile(file.absolutePath, "utf8");
    const parsed = frontmatter(source);
    return {
      id: file.path,
      title: heading(parsed.body, basename(file.path, ".md")),
      content: parsed.body,
    };
  }),
);

const utilities = utilityCatalog.map((utility) => ({
  id: utility.id,
  title: utility.title,
  harness: utility.harness,
  summary: utility.summary,
  capabilities: utility.capabilities,
  fileCount: inventory.filter((file) =>
    utility.prefix ? file.path.startsWith(utility.prefix) : file.path === utility.path,
  ).length,
}));

const digest = sha256(inventory.map((file) => `${file.path}\0${file.hash}`).join("\n")).slice(0, 24);
const referenceCount = skills.reduce((total, skill) => total + skill.references.length, 0);
const snapshot = {
  schemaVersion: 2,
  id: "fleet-resources",
  description: "AgentStart's fixed private resources for every managed fleet session.",
  digest,
  categories: categoryCatalog.map((category) => ({
    id: category.id,
    label: category.label,
    description: category.description,
  })),
  startingSkills: ["collab", "prompt", "search", "browser", "wiki"],
  skills,
  guidance,
  utilities,
  stats: {
    skills: skills.length,
    references: referenceCount,
    guidance: guidance.length,
    utilities: utilities.length,
    implementationFiles: inventory.length,
    adviceDocuments: skills.length + referenceCount + guidance.length,
  },
};

const serialized = JSON.stringify(snapshot);
if (retiredPiSpelling.test(serialized)) {
  throw new Error("refusing to publish a fleet snapshot containing a retired Pi spelling");
}

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${serialized}\n`);
console.log(
  `Snapshotted ${snapshot.stats.skills} skills, ${snapshot.stats.references} references, and ${snapshot.stats.utilities} utility summaries from the fixed fleet resources (${digest}).`,
);
