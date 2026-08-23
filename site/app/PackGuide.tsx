"use client";

import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

type Category = {
  id: string;
  label: string;
  description: string;
};

type AdviceReference = {
  id: string;
  title: string;
  content: string;
};

type AdviceSkill = {
  id: string;
  title: string;
  category: string;
  summary: string;
  description: string;
  content: string;
  references: AdviceReference[];
  dialects: {
    claude: string;
    codex: string;
    pi: string;
  };
};

type Guidance = {
  id: string;
  title: string;
  content: string;
};

type Utility = {
  id: string;
  title: string;
  harness: string;
  summary: string;
  capabilities: string[];
  fileCount: number;
};

type PackSnapshot = {
  schemaVersion: 2;
  id: string;
  description: string;
  digest: string;
  categories: Category[];
  startingSkills: string[];
  skills: AdviceSkill[];
  guidance: Guidance[];
  utilities: Utility[];
  stats: {
    skills: number;
    references: number;
    guidance: number;
    utilities: number;
    implementationFiles: number;
    adviceDocuments: number;
  };
};

type Selection =
  | { kind: "skill"; skillId: string; referenceId: string | null }
  | { kind: "guidance"; guidanceId: string };

const startingPrompts = [
  { id: "collab", label: "Start substantial work", prompt: "How should an agent work with me?" },
  { id: "prompt", label: "Hand work to an agent", prompt: "How do I turn this idea into a good brief?" },
  { id: "search", label: "Research the live web", prompt: "How do we find a current, cited answer?" },
  { id: "browser", label: "Use a signed-in site", prompt: "Can the agent click through this for me?" },
  { id: "wiki", label: "Keep the conclusion", prompt: "Where should this knowledge live?" },
];

const sharedGuidanceSummary =
  "The baseline operating rules every managed session receives: where work belongs, how agents collaborate, and which system boundaries must stay intact.";

function AdviceMarkdown({ content }: { content: string }) {
  return (
    <article className="advice-markdown">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
    </article>
  );
}

function readerScrollToTop() {
  document.querySelector(".guide-reader")?.scrollTo({ top: 0, behavior: "smooth" });
}

export function PackGuide() {
  const [snapshot, setSnapshot] = useState<PackSnapshot | null>(null);
  const [loadError, setLoadError] = useState(false);
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query.trim().toLowerCase());
  const [category, setCategory] = useState("all");
  const [selection, setSelection] = useState<Selection>({
    kind: "skill",
    skillId: "collab",
    referenceId: null,
  });
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
        const requested = new URLSearchParams(window.location.hash.slice(1));
        const skillId = requested.get("skill");
        const referenceId = requested.get("note");
        const guidanceId = requested.get("guidance");
        if (guidanceId && next.guidance.some((item) => item.id === guidanceId)) {
          setSelection({ kind: "guidance", guidanceId });
        } else if (skillId && next.skills.some((skill) => skill.id === skillId)) {
          const skill = next.skills.find((item) => item.id === skillId);
          setSelection({
            kind: "skill",
            skillId,
            referenceId: skill?.references.some((reference) => reference.id === referenceId)
              ? referenceId
              : null,
          });
        }
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

  const visibleSkills = useMemo(() => {
    if (!snapshot) return [];
    return snapshot.skills.filter((skill) => {
      if (category !== "all" && skill.category !== category) return false;
      if (!deferredQuery) return true;
      const searchable = [
        skill.id,
        skill.title,
        skill.summary,
        skill.description,
        skill.content,
        ...skill.references.flatMap((reference) => [reference.title, reference.content]),
      ]
        .join("\n")
        .toLowerCase();
      return searchable.includes(deferredQuery);
    });
  }, [category, deferredQuery, snapshot]);

  const selectedSkill =
    selection.kind === "skill"
      ? snapshot?.skills.find((skill) => skill.id === selection.skillId) ?? null
      : null;
  const selectedGuidance =
    selection.kind === "guidance"
      ? snapshot?.guidance.find((item) => item.id === selection.guidanceId) ?? null
      : null;
  const selectedReference =
    selection.kind === "skill" && selection.referenceId
      ? selectedSkill?.references.find((reference) => reference.id === selection.referenceId) ?? null
      : null;
  const selectedCategory = selectedSkill
    ? snapshot?.categories.find((item) => item.id === selectedSkill.category) ?? null
    : null;

  function selectSkill(skillId: string, jump = false) {
    setSelection({ kind: "skill", skillId, referenceId: null });
    window.history.replaceState(null, "", `#skill=${encodeURIComponent(skillId)}`);
    readerScrollToTop();
    if (jump) {
      window.requestAnimationFrame(() => {
        document.querySelector(".guide-shell")?.scrollIntoView({ behavior: "smooth" });
      });
    }
  }

  function selectReference(referenceId: string) {
    if (!selectedSkill) return;
    const nextReference = referenceId === "playbook" ? null : referenceId;
    setSelection({ kind: "skill", skillId: selectedSkill.id, referenceId: nextReference });
    const hash = new URLSearchParams({ skill: selectedSkill.id });
    if (nextReference) hash.set("note", nextReference);
    window.history.replaceState(null, "", `#${hash.toString()}`);
    readerScrollToTop();
  }

  function selectGuidance(jump = false) {
    const item = snapshot?.guidance[0];
    if (!item) return;
    setSelection({ kind: "guidance", guidanceId: item.id });
    window.history.replaceState(null, "", `#guidance=${encodeURIComponent(item.id)}`);
    readerScrollToTop();
    if (jump) {
      window.requestAnimationFrame(() => {
        document.querySelector(".guide-shell")?.scrollIntoView({ behavior: "smooth" });
      });
    }
  }

  if (loadError) {
    return (
      <section className="load-state" id="guide">
        <p className="eyebrow">Field guide unavailable</p>
        <h2>The common pack advice could not be loaded.</h2>
        <p>Refresh the page to try the generated guide again.</p>
      </section>
    );
  }

  if (!snapshot) {
    return (
      <section className="load-state" id="guide" role="status" aria-live="polite">
        <span className="loading-rule" />
        <p>Opening the common pack field guide…</p>
      </section>
    );
  }

  return (
    <section className="guide" id="guide">
      <div className="guide-intro">
        <div>
          <p className="eyebrow">Advice, not inventory · {snapshot.digest.slice(0, 8)}</p>
          <h2>Find the method for the job in front of you.</h2>
          <p>
            Common is the field guide every managed agent starts with. Search by what you
            want to accomplish; each result explains when the advice applies and carries the
            full playbook behind it.
          </p>
        </div>
        <dl className="guide-stats">
          <div><dt>Playbooks</dt><dd>{snapshot.stats.skills}</dd></div>
          <div><dt>Field notes</dt><dd>{snapshot.stats.references}</dd></div>
          <div><dt>Utilities</dt><dd>{snapshot.stats.utilities}</dd></div>
        </dl>
      </div>

      <div className="orientation-grid" aria-label="How the common pack works">
        <article>
          <span>Ask naturally</span>
          <strong>Start with the outcome.</strong>
          <p>The agent recognizes the situation and reaches for the relevant playbook.</p>
        </article>
        <article>
          <span>Follow the method</span>
          <strong>Advice shapes the work.</strong>
          <p>Each skill teaches when to act, what to inspect, and how to finish responsibly.</p>
        </article>
        <article>
          <span>Keep tools backstage</span>
          <strong>Utilities support the session.</strong>
          <p>Implementation travels with the pack, but only its purpose belongs in this guide.</p>
        </article>
      </div>

      <section className="starting-section" aria-labelledby="starting-title">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Good first questions</p>
            <h3 id="starting-title">Begin with something you want done.</h3>
          </div>
          <button type="button" className="text-button" onClick={() => selectGuidance(true)}>
            Read the shared session rules <span aria-hidden="true">↗</span>
          </button>
        </div>
        <div className="starting-prompts">
          {startingPrompts.map((item) => (
            <button type="button" key={item.id} onClick={() => selectSkill(item.id, true)}>
              <span>{item.label}</span>
              <strong>{item.prompt}</strong>
              <i aria-hidden="true">↘</i>
            </button>
          ))}
        </div>
      </section>

      <section className="utility-section" aria-labelledby="utility-title">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Quiet machinery</p>
            <h3 id="utility-title">What the pack supplies without asking you to read code.</h3>
          </div>
          <p>
            These are session capabilities, not advice documents. Their implementation stays
            out of the guide.
          </p>
        </div>
        <div className="utility-grid">
          {snapshot.utilities.map((utility) => (
            <article key={utility.id}>
              <header>
                <span>{utility.harness} utility</span>
                <small>{utility.fileCount === 1 ? "one implementation file" : `${utility.fileCount} implementation files`}</small>
              </header>
              <h4>{utility.title}</h4>
              <p>{utility.summary}</p>
              <ul>
                {utility.capabilities.map((capability) => <li key={capability}>{capability}</li>)}
              </ul>
            </article>
          ))}
        </div>
      </section>

      <div className="guide-shell">
        <aside className="guide-nav" aria-label="Common pack advice">
          <div className="guide-nav-head">
            <label className="intent-search">
              <span aria-hidden="true">⌕</span>
              <span className="sr-only">Search advice by intent</span>
              <input
                ref={searchRef}
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="What are you trying to do?"
              />
              <kbd>⌘ K</kbd>
            </label>
            <div className="category-list" aria-label="Filter advice by category">
              <button
                type="button"
                className={category === "all" ? "active" : ""}
                onClick={() => setCategory("all")}
              >
                <strong>Everything</strong><span>{snapshot.stats.skills}</span>
              </button>
              {snapshot.categories.map((item) => (
                <button
                  type="button"
                  key={item.id}
                  className={category === item.id ? "active" : ""}
                  onClick={() => setCategory(item.id)}
                  title={item.description}
                >
                  <strong>{item.label}</strong>
                  <span>{snapshot.skills.filter((skill) => skill.category === item.id).length}</span>
                </button>
              ))}
            </div>
            <p className="result-count">
              {visibleSkills.length} {visibleSkills.length === 1 ? "playbook" : "playbooks"}
              {deferredQuery ? ` matching “${deferredQuery}”` : ""}
            </p>
          </div>

          <div className="skill-list">
            {visibleSkills.map((skill) => (
              <button
                type="button"
                key={skill.id}
                className={selection.kind === "skill" && selection.skillId === skill.id ? "selected" : ""}
                onClick={() => selectSkill(skill.id)}
              >
                <span>{snapshot.categories.find((item) => item.id === skill.category)?.label}</span>
                <strong>{skill.title}</strong>
                <p>{skill.summary}</p>
                <small>{skill.references.length > 0 ? `${skill.references.length} related notes` : "one complete playbook"}</small>
              </button>
            ))}
            {visibleSkills.length === 0 ? (
              <div className="no-results">
                <span>0</span>
                <p>No playbook uses those words yet.</p>
                <button type="button" onClick={() => { setQuery(""); setCategory("all"); }}>
                  Show all advice
                </button>
              </div>
            ) : null}
          </div>
        </aside>

        <div className="guide-reader">
          {selectedSkill ? (
            <>
              <header className="reader-head">
                <div className="reader-kicker">
                  <span>Advice playbook</span>
                  {selectedCategory ? <small>{selectedCategory.label}</small> : null}
                </div>
                <h3>{selectedSkill.title}</h3>
                <p>{selectedSkill.summary}</p>
                <dl className="dialect-row" aria-label={`${selectedSkill.title} in each harness`}>
                  <div><dt>Claude</dt><dd><code>{selectedSkill.dialects.claude}</code></dd></div>
                  <div><dt>Codex</dt><dd><code>{selectedSkill.dialects.codex}</code></dd></div>
                  <div><dt>Pi</dt><dd><code>{selectedSkill.dialects.pi}</code></dd></div>
                </dl>
              </header>

              <section className="purpose-panel">
                <span>What it is for</span>
                <p>{selectedSkill.description}</p>
              </section>

              <div className="reading-toolbar">
                <label>
                  <span>Reading</span>
                  <select
                    value={selectedReference?.id || "playbook"}
                    onChange={(event) => selectReference(event.target.value)}
                  >
                    <option value="playbook">Core playbook</option>
                    {selectedSkill.references.length > 0 ? (
                      <optgroup label="Related field notes">
                        {selectedSkill.references.map((reference) => (
                          <option key={reference.id} value={reference.id}>{reference.title}</option>
                        ))}
                      </optgroup>
                    ) : null}
                  </select>
                </label>
                <span>{selectedReference ? "Related field note" : "Canonical advice"}</span>
              </div>

              <AdviceMarkdown content={selectedReference?.content || selectedSkill.content} />
            </>
          ) : selectedGuidance ? (
            <>
              <header className="reader-head">
                <div className="reader-kicker"><span>Shared baseline</span><small>Every managed session</small></div>
                <h3>Session Guidance</h3>
                <p>{sharedGuidanceSummary}</p>
              </header>
              <section className="purpose-panel">
                <span>What it is for</span>
                <p>
                  This is the common operating context beneath every skill: ownership boundaries,
                  collaboration expectations, installation rules, and the vocabulary agents share.
                </p>
              </section>
              <AdviceMarkdown content={selectedGuidance.content} />
            </>
          ) : (
            <div className="empty-reader"><p>Choose a playbook to begin.</p></div>
          )}
        </div>
      </div>
    </section>
  );
}
