# Use native Codex invocation profiles

Funk owns personal Codex preferences; AgentStart's existing harness shim copies them into a unique native profile, adds invocation cwd/project trust, and removes the copy when Codex exits. Keeping the normal Codex home preserves account and history integration while preventing trust writes and concurrent launches from rewriting the authored source. Native project and CLI precedence remain intact; utility and remote-server commands pass through without profiles.
