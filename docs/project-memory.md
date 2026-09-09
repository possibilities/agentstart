# Checking project document integrity

AgentGuidance owns the writing doctrine. This check supports it by finding
mechanical defects; it does not judge whether a glossary is useful or an ADR
preserves the right reason.

Run it against one or more explicit checkouts:

```sh
python3 scripts/check-project-docs.py
python3 scripts/check-project-docs.py ../agentvoice ../smolmux
```

With no paths it checks AgentStart. The existing `tests/validate.sh` runs its
fixtures and the AgentStart check. For a fleet change, pass the affected
checkouts explicitly; the check does not discover the machine or require every
repository to be installed. `--json` emits the same findings as structured data.

The inventory is Git-tracked plus non-ignored new Markdown files at the root
and under `docs/`. Missing relative file targets, broken document symlinks and
duplicate four-digit ADR filename identifiers fail the check. ADR identifiers
are unique within each directory under `docs/adr/`; an explicit historical
subdirectory remains its own namespace. New records must also check Git history
before choosing a number, because this check cannot detect deleted identities.

It recognizes ordinary inline/image links and reference definitions, including
angle-wrapped destinations and percent-encoded paths. Fenced/indented code,
inline code, external URLs, absolute machine paths and home-relative paths are
excluded. Anchor fragments are stripped: anchor validity, wiki links, bare
backtick paths, complex nested Markdown link syntax and external URL health
still need review. Linked directories are valid targets.

An existing glossary missing from the root entrypoint and replacement language
without a complete local ADR link are advisory warnings. Prose cannot reliably
tell the checker which clause a successor changed. Review both records and use
full file links when citing a replacement.

Use repeatable `--exclude REPO_RELATIVE_GLOB` only for a documented exception,
such as foreign historical material with its own link environment. Exclusions
apply to every supplied checkout and appear in the invocation; do not hide a
new defect with a broad exception. No file count, length, required empty file,
uniform status format or identical fleet footer is enforced.
