import { PackExplorer } from "./PackExplorer";

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="wordmark" href="#top" aria-label="Common Pack home">
          <span className="wordmark-mark" aria-hidden="true">C</span>
          <span>Common Pack</span>
        </a>
        <div className="header-meta">
          <span>AgentStart capability atlas</span>
          <a href="#explorer">Browse every file ↓</a>
        </div>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">The default capability pack</p>
          <h1>
            One field manual.
            <span>Three native dialects.</span>
          </h1>
          <p className="hero-deck">
            Common gathers the skills, guidance, scripts, examples, and harness
            resources that travel with every managed agent session. Explore the
            actual installed content—nothing summarized away.
          </p>
          <a className="primary-link" href="#explorer">
            Open the atlas <span aria-hidden="true">↘</span>
          </a>
        </div>

        <div className="transmission" aria-label="How common appears in each harness">
          <div className="transmission-origin">
            <span className="signal-pulse" aria-hidden="true" />
            <div>
              <span className="micro-label">Source</span>
              <strong>common</strong>
              <small>portable resources</small>
            </div>
          </div>
          <div className="transmission-lines" aria-hidden="true">
            <i />
            <i />
            <i />
          </div>
          <div className="harness-stack">
            <article>
              <span className="harness-index">A</span>
              <div><strong>Claude</strong><small>synthetic agent plugin</small></div>
              <code>/agent:build</code>
            </article>
            <article>
              <span className="harness-index">B</span>
              <div><strong>Codex</strong><small>standalone skill roots</small></div>
              <code>$build</code>
            </article>
            <article>
              <span className="harness-index">C</span>
              <div><strong>Pi</strong><small>explicit resource paths</small></div>
              <code>/build</code>
            </article>
          </div>
        </div>
      </section>

      <section className="thesis-strip" aria-label="Common pack principles">
        <p><span>01</span> One canonical bundle</p>
        <p><span>02</span> Native session histories stay native</p>
        <p><span>03</span> Session packs compose without ambient discovery</p>
      </section>

      <PackExplorer />
    </main>
  );
}
