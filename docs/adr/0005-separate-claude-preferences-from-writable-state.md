# Separate Claude preferences from writable state

Stow an authored `~/.claude/preferences.json` and load it through native
`--settings`, because Claude's writable settings accumulate generated context
and integration commands. Record workspace trust under Claude's native local
config lock before managed launches, preserving the existing account and
session home without storing directory history in dotfiles or modifying Claude.
