#!/usr/bin/env python3
"""Check local document identity and file links without judging prose quality."""

import argparse
import fnmatch
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit


ADR_NAME = re.compile(r"^(\d{4})[-_].*\.md$")
INLINE_LINK = re.compile(
    r"!?\[[^\]\n]*\]\(\s*(<[^>\n]+>|[^\s)]+)(?:\s+[\"'][^\n]*?[\"'])?\s*\)"
)
REFERENCE = re.compile(r"^ {0,3}\[[^\]\n]+\]:\s*(<[^>\n]+>|\S+)")


def prose_lines(text):
    """Skip fenced/indented code and inline code while preserving line numbers."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence or line.startswith("    ") or line.startswith("\t"):
            continue
        yield number, re.sub(r"(`+).*?\1", "", line)


def local_links(text):
    for number, line in prose_lines(text):
        matches = list(INLINE_LINK.finditer(line))
        reference = REFERENCE.match(line)
        if reference:
            matches.append(reference)
        for match in matches:
            target = match.group(1).strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            path = unquote(parsed.path)
            # Absolute and home-relative paths describe the operator's machine.
            if path.startswith(("/", "~")):
                continue
            yield number, path


def documents(root, excludes):
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    files = []
    for name in sorted(set(result.stdout.split("\0")) - {""}):
        path = Path(name)
        if path.suffix.lower() != ".md":
            continue
        if len(path.parts) != 1 and path.parts[0] != "docs":
            continue
        if any(fnmatch.fnmatchcase(name, pattern) for pattern in excludes):
            continue
        file = root / path
        # An unstaged deletion is no longer in the working document log.
        # A broken symlink is still an entrypoint that needs repair.
        if file.exists() or file.is_symlink():
            files.append(path)
    return files


def check_repository(root, excludes=()):
    root = root.resolve()
    findings = []

    def report(level, code, file, line, message):
        findings.append(dict(level=level, code=code, file=str(file), line=line, message=message))

    files = documents(root, excludes)
    identities = {}
    texts = {}
    for relative in files:
        path = root / relative
        if not path.exists():
            report("error", "broken-symlink", relative, 1, "document symlink target is missing")
            continue
        if path.is_dir():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            report("error", "unreadable-document", relative, 1, str(error))
            continue
        texts[relative.as_posix()] = text
        match = ADR_NAME.match(relative.name)
        if match and relative.parts[:2] == ("docs", "adr"):
            # A separate historical directory is a separate, explicit namespace.
            key = (relative.parent, match.group(1))
            if key in identities:
                report("error", "duplicate-adr-id", relative, 1,
                       f"ADR {key[1]} also belongs to {identities[key]}")
            else:
                identities[key] = relative
        links = list(local_links(text))
        for number, target in links:
            if not (path.parent / target).exists():
                report("error", "missing-local-target", relative, number, f"missing file target: {target}")
        if match and re.search(r"superseded|supersedes|replaced by (?:ADR|\[?\d{4})",
                               "\n".join(text.splitlines()[:12]), re.I):
            if not any(ADR_NAME.match(Path(target).name) for _, target in links):
                report("warning", "replacement-link", relative, 1,
                       "replacement language has no complete local ADR file link; review the intended scope")
    if "CONTEXT.md" in texts and "CONTEXT.md" not in texts.get("AGENTS.md", ""):
        report("warning", "glossary-entrypoint", "AGENTS.md", 1,
               "CONTEXT.md exists but the root entrypoint does not name it")
    return dict(repository=str(root), documents=len(files), findings=findings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repositories", nargs="*", type=Path, default=[Path(__file__).resolve().parent.parent])
    parser.add_argument("--exclude", action="append", default=[], metavar="REPO_RELATIVE_GLOB",
                        help="explicit document exception, applied to each repository (repeatable)")
    parser.add_argument("--json", action="store_true", help="emit a structured report")
    args = parser.parse_args()
    reports = []
    for root in args.repositories:
        try:
            reports.append(check_repository(root, args.exclude))
        except (OSError, subprocess.CalledProcessError) as error:
            parser.exit(2, f"check-project-docs: cannot inventory {root}: {error}\n")
    errors = sum(item["level"] == "error" for report in reports for item in report["findings"])
    warnings = sum(item["level"] == "warning" for report in reports for item in report["findings"])
    if args.json:
        print(json.dumps(dict(repositories=reports, errors=errors, warnings=warnings), indent=2))
    else:
        for report in reports:
            for item in report["findings"]:
                print(f"{report['repository']}/{item['file']}:{item['line']}: "
                      f"{item['level']} [{item['code']}] {item['message']}")
        count = sum(report["documents"] for report in reports)
        print(f"Project docs: {count} documents in {len(reports)} repositories; {errors} errors, {warnings} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
