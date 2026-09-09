## Guidelines

- Reuse collected research with `brain` when prior reading is relevant, and
  consult `chats` when prior sessions may contain relevant work. Do not add an
  unrelated lookup to a task that already has the necessary evidence.
- Keep ongoing, tracked work visible with `board`: use its existing item or
  claim the relevant one, and close it when the authorized work is finished.
  A simple answer or isolated small edit does not need a new tracking ritual.
- Use AgentNotify through the `notifications` skill when work the human is
  waiting for finishes or stalls while they are away. It owns the durable
  notification inbox and terminal-notifier-compatible CLI; prefer its MCP for
  structured calls. Legacy callers use the AgentStart `terminal-notifier`
  router, which retains the original notifier as an availability fallback
  before submission; the `notify` skill explains it. Sound is opt-in; time-sensitive delivery does not guarantee
  a Focus bypass. Read is not completion or approval.
- In someone else's Clone (`~/source/<upstream-owner>--<repo>`), orient before
  working: verify `upstream` names the original repository, `fork` names our
  optional fork, and the branch is the one the task means — the default, or
  our fork's branch when we carry patches — then pull and fast-forward. A
  genuinely diverged branch is reported, not resolved in passing.
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
- Upstream messages — a pull request and its body, a comment, or a reply to a
  reviewer — require the human's authorization for that scope. Existing
  explicit authorization counts. Prepare the concrete result before asking
  for any missing decision. Clear code changes answering a review may proceed
  within the task; a recap comment still needs communication authority.
  Review offered changes before pushing, using bounded independent review
  when required by the project or useful and permitted by the active role.
- A fleet full-screen TUI uses exactly one complete design language: fxnk or
  Signal Room. Never combine their tokens, components, borders, layout
  vocabulary, or interaction shell. An explicit user or project choice wins;
  otherwise infer from established repository precedent, and ask the human
  when that evidence is not reliable. For Signal Room, read the
  `fleet-tui-design` wiki page and the design-language page it opens with. For
  fxnk, read `~/code/fxnk/style/STYLE.md`. The contracts live there, not here.
