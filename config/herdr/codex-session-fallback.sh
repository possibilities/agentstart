#!/bin/sh
# AGENTSTART_MANAGED_CODEX_HERDR_SESSION_FALLBACK=1
# Temporary bridge for Herdr's Codex integration v8. Delete this file and its
# dedicated installer when a newer integration reliably reports SessionStart.

set -eu

# The hook is registered in the normal Codex home so it can retain Codex's
# native hook trust. Its behavior is narrower: only a Codex process launched
# through AgentLaunch inside Herdr may report identity.
[ "${AGENTLAUNCH_LAUNCH:-}" = "1" ] || exit 0
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
[ -n "${CODEX_THREAD_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

managed_hook="${CODEX_HOME:-${HOME:-}/.codex}/herdr-agent-state.sh"
managed_version="$({ sed -n 's/^# HERDR_INTEGRATION_VERSION=//p' "$managed_hook" 2>/dev/null || true; } | head -n 1)"
case "$managed_version" in
  ''|*[!0-9]*) ;;
  *) [ "$managed_version" -le 8 ] || exit 0 ;;
esac

hook_input_file="$(mktemp "${TMPDIR:-/tmp}/agentstart-herdr-codex-fallback.XXXXXX")" || exit 0
trap 'rm -f -- "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

AGENTSTART_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import json
import os
import shutil
import subprocess
import sys
import time

try:
    with open(os.environ["AGENTSTART_HOOK_INPUT_FILE"], encoding="utf-8") as handle:
        hook_input = json.load(handle)
except Exception:
    raise SystemExit(0)

if hook_input.get("hook_event_name") != "SessionStart":
    raise SystemExit(0)

# A nonempty transcript identifies a resume. Herdr already knows the resumed
# session; the v8 gap affects only a newly created root conversation.
transcript_path = hook_input.get("transcript_path")
if isinstance(transcript_path, str) and transcript_path.strip():
    raise SystemExit(0)

session_id = hook_input.get("session_id")
thread_id = os.environ.get("CODEX_THREAD_ID")
if not isinstance(session_id, str) or not session_id or session_id != thread_id:
    raise SystemExit(0)

herdr_bin = os.environ.get("HERDR_BIN_PATH") or shutil.which("herdr")
if not herdr_bin:
    raise SystemExit(0)

command = [
    herdr_bin,
    "pane",
    "report-agent-session",
    os.environ["HERDR_PANE_ID"],
    "--source",
    "herdr:codex",
    "--agent",
    "codex",
    "--seq",
    str(time.time_ns()),
    "--agent-session-id",
    session_id,
]
source = hook_input.get("source")
if isinstance(source, str) and source:
    command.extend(["--session-start-source", source])

try:
    subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=2,
        check=False,
    )
except Exception:
    # Session startup must never fail because the temporary reporting bridge
    # cannot reach a closing pane or server.
    pass
PY
