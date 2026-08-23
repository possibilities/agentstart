"use client";

import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

type FileKind = "manifest" | "guidance" | "skill" | "support" | "pi";

type PackFile = {
  path: string;
  title: string;
  description: string | null;
  skill: string | null;
  kind: FileKind;
  language: string;
  mime: string;
  encoding: "utf8" | "base64";
  size: number;
  hash: string;
  content: string;
};

type PackSnapshot = {
  schemaVersion: number;
  id: string;
  description: string;
  digest: string;
  stats: {
    skills: number;
    files: number;
    bytes: number;
    guidance: number;
    piResources: number;
  };
  files: PackFile[];
};

type Scope = "all" | FileKind;

const scopes: Array<{ id: Scope; label: string }> = [
  { id: "all", label: "All" },
  { id: "skill", label: "Skills" },
  { id: "support", label: "References" },
  { id: "guidance", label: "Guidance" },
  { id: "pi", label: "Pi" },
];

const startingPoints = [
  {
    path: "capability.json",
    kicker: "Start here",
    title: "The pack contract",
    note: "What common declares and which resource roots it exports.",
  },
  {
    path: "skills/collab/SKILL.md",
    kicker: "Workflow",
    title: "How requests are routed",
    note: "The human-in-the-loop path from question to sketch to build.",
  },
  {
    path: "skills/build/SKILL.md",
    kicker: "Execution",
    title: "How approved work ships",
    note: "The autonomous counterpart that turns a complete brief into work.",
  },
  {
    path: "skills/fleet/MAP.md",
    kicker: "System map",
    title: "How the fleet connects",
    note: "Runtime calls, skill routes, services, and pinned dependencies.",
  },
];

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(bytes < 10240 ? 1 : 0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function kindLabel(kind: FileKind) {
  return {
    manifest: "manifest",
    guidance: "guidance",
    skill: "skill",
    support: "reference",
    pi: "pi resource",
  }[kind];
}

function pathTitle(file: PackFile) {
  if (file.kind === "skill" && file.skill) return file.skill;
  return file.title === file.path.split("/").at(-1) ? file.path : file.title;
}

function DocumentBody({ file }: { file: PackFile }) {
  if (file.encoding === "base64") {
    return (
      <div className="image-preview">
        {/* The snapshot contains trusted installed pack assets. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={`data:${file.mime};base64,${file.content}`} alt={file.title} />
        <p>{formatBytes(file.size)} · embedded pack asset</p>
      </div>
    );
  }

  if (file.language === "markdown") {
    if (file.content.trim() === "") {
      return (
        <div className="empty-document">
          <span aria-hidden="true">∅</span>
          <h3>This file is intentionally empty.</h3>
          <p>The path is part of the pack, but it currently contributes no text.</p>
        </div>
      );
    }
    return (
      <article className="markdown-body">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{file.content}</ReactMarkdown>
      </article>
    );
  }

  return (
    <pre className="raw-document" tabIndex={0} aria-label={`${file.path} source`}>
      <code>{file.content}</code>
    </pre>
  );
}

export function PackExplorer() {
  const [snapshot, setSnapshot] = useState<PackSnapshot | null>(null);
  const [loadError, setLoadError] = useState(false);
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query.trim().toLowerCase());
  const [scope, setScope] = useState<Scope>("all");
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetch("/common-pack.json", { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error(`snapshot returned ${response.status}`);
        return response.json() as Promise<PackSnapshot>;
      })
      .then((next) => {
        setSnapshot(next);
        const requested = decodeURIComponent(window.location.hash.slice(1));
        const initial = next.files.some((file) => file.path === requested)
          ? requested
          : "skills/collab/SKILL.md";
        setSelectedPath(initial);
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setLoadError(true);
      });
    return () => controller.abort();
  }, []);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchRef.current?.focus();
      }
      if (event.key === "Escape" && document.activeElement === searchRef.current) {
        setQuery("");
        searchRef.current?.blur();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const visibleFiles = useMemo(() => {
    if (!snapshot) return [];
    return snapshot.files.filter((file) => {
      if (scope !== "all" && file.kind !== scope) return false;
      if (!deferredQuery) return true;
      return (
        file.path.toLowerCase().includes(deferredQuery) ||
        file.title.toLowerCase().includes(deferredQuery) ||
        (file.description?.toLowerCase().includes(deferredQuery) ?? false) ||
        (file.encoding === "utf8" && file.content.toLowerCase().includes(deferredQuery))
      );
    });
  }, [deferredQuery, scope, snapshot]);

  const selected = useMemo(
    () => snapshot?.files.find((file) => file.path === selectedPath) ?? null,
    [selectedPath, snapshot],
  );

  function selectFile(path: string) {
    setSelectedPath(path);
    setCopied(false);
    window.history.replaceState(null, "", `#${encodeURIComponent(path)}`);
    document.querySelector(".document-pane")?.scrollTo({ top: 0, behavior: "smooth" });
    if (window.innerWidth < 820) {
      document.querySelector(".document-pane")?.scrollIntoView({ behavior: "smooth" });
    }
  }

  async function copyPath() {
    if (!selected) return;
    await navigator.clipboard.writeText(selected.path);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  if (loadError) {
    return (
      <section className="load-state" id="explorer">
        <p className="eyebrow">Snapshot unavailable</p>
        <h2>The pack index could not be loaded.</h2>
        <p>Refresh the page to try the generated snapshot again.</p>
      </section>
    );
  }

  if (!snapshot) {
    return (
      <section className="load-state" id="explorer" role="status" aria-live="polite">
        <span className="loading-rule" />
        <p>Reading the common pack…</p>
      </section>
    );
  }

  return (
    <section className="atlas" id="explorer">
      <div className="atlas-intro">
        <div>
          <p className="eyebrow">Installed snapshot · {snapshot.digest.slice(0, 8)}</p>
          <h2>Learn the system, then read the source.</h2>
          <p>
            Start with a governing document or search every byte of the pack.
            Supporting files stay attached to the skill that owns them.
          </p>
        </div>
        <dl className="pack-stats">
          <div><dt>Skills</dt><dd>{snapshot.stats.skills}</dd></div>
          <div><dt>Files</dt><dd>{snapshot.stats.files}</dd></div>
          <div><dt>Payload</dt><dd>{formatBytes(snapshot.stats.bytes)}</dd></div>
        </dl>
      </div>

      <div className="starting-grid">
        {startingPoints.map((item) => (
          <button type="button" key={item.path} onClick={() => selectFile(item.path)}>
            <span>{item.kicker}</span>
            <strong>{item.title}</strong>
            <small>{item.note}</small>
            <i aria-hidden="true">↗</i>
          </button>
        ))}
      </div>

      <div className="explorer-shell">
        <aside className="file-pane" aria-label="Common pack files">
          <div className="file-pane-head">
            <label className="search-box">
              <span aria-hidden="true">⌕</span>
              <span className="sr-only">Search pack content</span>
              <input
                ref={searchRef}
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={`Search ${snapshot.stats.files} files`}
              />
              <kbd>⌘ K</kbd>
            </label>
            <div className="scope-tabs" aria-label="Filter files">
              {scopes.map((item) => (
                <button
                  type="button"
                  key={item.id}
                  className={scope === item.id ? "active" : ""}
                  onClick={() => setScope(item.id)}
                >
                  {item.label}
                </button>
              ))}
            </div>
            <p className="result-count">
              {visibleFiles.length} {visibleFiles.length === 1 ? "file" : "files"}
              {deferredQuery ? ` matching “${deferredQuery}”` : ""}
            </p>
          </div>

          <div className="file-list">
            {visibleFiles.map((file) => (
              <button
                type="button"
                key={file.path}
                className={selectedPath === file.path ? "selected" : ""}
                onClick={() => selectFile(file.path)}
              >
                <span className={`file-kind kind-${file.kind}`}>{kindLabel(file.kind)}</span>
                <strong>{pathTitle(file)}</strong>
                <small>{file.path}</small>
                <em>{formatBytes(file.size)}</em>
              </button>
            ))}
            {visibleFiles.length === 0 ? (
              <div className="no-results">
                <span>0</span>
                <p>No pack files match this search.</p>
                <button type="button" onClick={() => { setQuery(""); setScope("all"); }}>
                  Clear filters
                </button>
              </div>
            ) : null}
          </div>
        </aside>

        <div className="document-pane">
          {selected ? (
            <>
              <header className="document-head">
                <div>
                  <span className={`file-kind kind-${selected.kind}`}>{kindLabel(selected.kind)}</span>
                  <h3>{pathTitle(selected)}</h3>
                  {selected.description ? <p>{selected.description}</p> : null}
                </div>
                <button type="button" onClick={copyPath} aria-label={`Copy ${selected.path}`}>
                  {copied ? "Copied" : "Copy path"}
                </button>
                <code>{selected.path}</code>
              </header>
              <DocumentBody file={selected} />
            </>
          ) : (
            <div className="empty-document"><p>Select a file to read it.</p></div>
          )}
        </div>
      </div>
    </section>
  );
}
