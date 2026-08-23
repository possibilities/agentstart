import { PackGuide } from "./PackGuide";

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="wordmark" href="#top" aria-label="Common Pack home">
          <span className="wordmark-mark" aria-hidden="true">C</span>
          <span>Common Pack</span>
        </a>
        <div className="header-meta">
          <span>AgentStart advice field guide</span>
          <a href="#guide">Find the right playbook ↓</a>
        </div>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow">What every managed session already knows</p>
          <h1>
            Your agents arrive
            <span>with a field guide.</span>
          </h1>
          <p className="hero-deck">
            Common teaches agents how to collaborate, research, operate tools,
            build products, and preserve what they learn. Browse the advice by
            intent; leave the implementation backstage.
          </p>
          <a className="primary-link" href="#guide">
            Open the field guide <span aria-hidden="true">↘</span>
          </a>
        </div>

        <div className="transmission" aria-label="How common appears in each harness">
          <div className="transmission-origin">
            <span className="signal-pulse" aria-hidden="true" />
            <div>
              <span className="micro-label">Source</span>
              <strong>common</strong>
              <small>shared advice</small>
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
        <p><span>01</span> Start with what you want done</p>
        <p><span>02</span> A playbook teaches the method</p>
        <p><span>03</span> Each harness speaks natively</p>
      </section>

      <PackGuide />
    </main>
  );
}
