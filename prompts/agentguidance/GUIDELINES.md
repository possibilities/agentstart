## Guidelines

- Reuse collected research with `brain` when prior reading is relevant, and
  consult `chats` when prior sessions may contain relevant work. Do not add an
  unrelated lookup to a task that already has the necessary evidence.
- Managers keep substantive work visible with `hud`: default toward speculative
  durable Work when voice intent plausibly represents a substantive question,
  request or follow-up. Temporary over-tracking that can later be merged, cancelled
  or closed is preferable to invisible lost work. Keep scope, disposition and next
  action current, reconciling at start/resume and meaningful boundaries. New and
  current Work stays active unless the human explicitly
  requests waiting or paused; dependencies, blockers, validation and needed human
  responses instead get a truthful next action and, when supported, Needs you entry.
  Never dispatch a worker without corresponding Work: create/update
  Work, prepare its Assignment, dispatch, then bind the native turn; immediately
  reconcile any dispatch-first failure or race. Routing receipts and native dispatch
  never replace Work or Result. Workers report to their parent; managers record and
  review those reports under their own actor with worker attribution. Keep related
  Work active and actionable until the human acknowledges a substantive Result or provides its
  required approval, validation or decision; presentation and silence are not that
  response. Follow up contextually, respecting hold and unrelated conversation;
  do not invent timed reminders. For limited resources, reconcile the HUD
  resource/lease record
  at start/resume and at grant, claim, holder/scope change and release. Include
  still-valid explicit scoped grants already supplied in session/APPEND context;
  generic instructions or stale grant text confer no authority. Record the actual
  grant/claim before use or onward handoff; notification bookends do not replace
  HUD recording. Retain the actual human/self/other-agent holder and stable identity,
  exact scope/team
  coverage, exclusive/shared capacity and rules, direct-user or explicitly
  affirmative resolved Attention/AgentNotify grant evidence, and physical-state evidence,
  recheck and expiry. A HUD record is never permission; resolve conflict or
  uncertainty before use. Missing agents, expiry and revocation do not prove
  physical release. Tiny replies need no record. Legacy Board history stays
  read-only; do not dual-write or redirect new work into it.
- Use AgentNotify through the `notifications` skill when work the human is
  waiting for finishes or stalls while they are away. It owns the durable
  notification inbox and terminal-notifier-compatible CLI; prefer its MCP for
  structured calls. Legacy callers use the AgentStart `terminal-notifier`
  router, which submits only through AgentNotify and fails before submission
  when AgentNotify is unavailable; the `notify` skill explains it. Sound is opt-in; time-sensitive delivery does not guarantee
  a Focus bypass. Read is not completion or approval.
- In someone else's Clone (`~/source/<upstream-owner>--<repo>`), orient before
  working: verify `upstream` names the original repository and `fork` names our
  optional fork. Detect any choice to create, maintain, rebase or apply a patch
  carried against the external upstream before modifying the fork. It requires
  explicit human approval after surfacing the need, alternatives, ongoing
  maintenance burden and a recommended non-patch route when available. Once
  approved, verify the branch is the one the task means, then pull and
  fast-forward. Report a genuinely diverged branch rather than resolving it in
  passing. Ordinary authorized work in a first-party repository continues under
  that repository's instructions without this additional gate.
- A fork we patch is owned by a workshop repository (`fxnk` for Fx, `zmax`
  for zmx): its `MAINTAIN.md` is the contract for that fork, `/maintain` the
  procedure, and `integration` the only ref a consumer binds — through the
  workshop's own consumer step, never by hand. Upstream pull requests are
  evidence, not dependencies, and nothing moves their branches in passing.
  The `fork-rebase-policy` wiki page is the overview, not the contract.
- Honor the checkout, worktree, branch, and ownership assigned to the task.
  When an authorized change needs isolation, create or reuse an owned
  worktree under the active role's workflow. Do not reshape another worker's
  branch or worktree. Resolve conflicting ownership before depending on it;
  routine isolation does not require the user to name the Git operation.
- Build forward: the new shape replaces the old. Shims, deprecation
  windows, and migrations are opt-in — name what breaks and for whom
  before a breaking change lands; the softer path is asked for, never
  assumed.
- Before making or reviewing design decisions, consult the current
  [Vercel design guidelines](https://vercel.com/design.md) and use their
  principles as the baseline for the reasoning. Consult the relevant design
  documentation and guidelines in the wiki, beginning with `Vercel design
  guidance for native fleet apps` and the medium- or product-specific contract.
  Apply the project's established design language and explicit human direction
  on top; this is a decision-making foundation, not an instruction to imitate
  Vercel's brand.
- Repository guidance is `AGENTS.md` at the repo root, with `CLAUDE.md` a
  symlink to it — or, where tooling refuses tracked symlinks, a short
  pointer file naming `AGENTS.md`; never a second set of instructions.
- Do not use harness-provided agent memory. Persistent instructions live only
  in repository `AGENTS.md` or in global guidance maintained in
  `~/code/agentstart` and/or `~/code/agentguidance`. This concerns persistent
  instructions; temporary session working notes and native continuation
  context remain appropriate. The `document-placement-policy` wiki page
  records the distinction.
- Place global personal guidance tied to the `~/code/agent*` fleet in
  `~/code/agentstart`; reserve `~/code/agentguidance` for reusable general
  agent doctrine that is not specific to this fleet or operator.
- Route documents by reader and lifetime: asked-for documents, finished
  research worth finding again, and ruling decisions go to the wiki. The
  repo keeps what it owns (`AGENTS.md`,
  `CONTEXT.md`, `README`, ADRs, the docs that ship with the code), and
  successor-session context is a dated `~/handoffs/` file, deleted by its
  consumer. The `document-placement-policy` wiki page is the contract.
- Use `wiki` for durable authored knowledge that belongs in the shared wiki.
  For a requested document, presentation, spreadsheet, image, or other file,
  use the applicable artifact tools and requested destination. Publication
  still follows the user's scope; creating a file is not a request to publish
  it elsewhere. For a requested GitHub Gist, create it from the requested
  source file and open it with
  `gh gist create FILE --desc "…" --web`; Gists are secret/unlisted by
  default, so use `--public` only when public indexing was explicitly
  requested. If the Gist already exists, do not create a duplicate: open it
  with `gh gist view GIST_ID --web`.
- Cap searches at the source, not the reader: `grep -m N`, not `| head`,
  and `< /dev/null` on a grep inside a `while read` loop — some harness
  grep engines outlive the pipe and eat the loop's stdin.
- Never use raw shell backgrounding (`command &`, `nohup`, `disown`) to keep
  agent-launched work alive. Use the harness's managed long-lived process
  facility; for a TUI, REPL, interactive CLI, shell process, or anything that
  needs a PTY, load `terminal-control`, use a named session, and stop it in
  cleanup unless the human explicitly asked to retain it. An unmanaged child
  can outlive its shell with revoked terminal descriptors and spin forever.
- A clipboard copy leaves nothing on screen, so notify what landed there.
- Mint a new project with `ghinit`: run it bare from inside the new
  directory directly under `~/code`, or pass a name and it creates
  `~/code/<name>` first. Either way it initializes the repository and
  binds a private GitHub origin with the first push — never hand-assemble
  `git init` and `gh repo create`.
- Before recommending or preparing an upstream issue or pull request, inspect
  the current `CONTRIBUTING`, `SECURITY`, issue and pull-request templates and
  reporting channels. Assess recent repository behavior for maintainer
  preferences, accepted contribution patterns, review expectations and
  communication norms. Opening or materially updating an upstream issue or pull
  request requires explicit human approval of the concrete reviewable action;
  existing explicit authorization for that exact scope counts. This includes a
  pull-request body, patch-set update, issue or review comment, and reviewer
  reply. Clear first-party code changes remain authorized by their task and
  repository instructions, but a recap comment still needs communication
  authority. Review offered changes before pushing, using bounded independent
  review when required by the project or useful and permitted by the active role.
- A fleet full-screen TUI uses exactly one complete design language: fxnk or
  Signal Room. Never combine their tokens, components, borders, layout
  vocabulary, or interaction shell. An explicit user or project choice wins;
  otherwise infer from established repository precedent, and ask the human
  when that evidence is not reliable. For Signal Room, read the
  `fleet-tui-design` wiki page and the design-language page it opens with. For
  fxnk, read `~/code/fxnk/style/STYLE.md`. The contracts live there, not here.
