# 0012: Separate conversational hold intent and spoken ownership

Accepted September 14, 2026 after read-only Phase 3 qualification. Extends the
manager/worker roles in [0006](0006-own-manager-worker-roles.md) and the
conversational front guidance in [0009](0009-conversational-front-selective-managers.md).

An explicit conversational hold delays human presentation while authorized work,
internal returns and independent dependencies continue. Physical microphone and
speaker commands/status, push-to-talk, and label discussion do not set or clear
conversational hold. Preserve unmistakable addressed requests, including mute;
ambiguous audio language and mere typed task steering do not imply resumption.

In a voice exchange with a separate speech front, that front owns the spoken
hold/resume acknowledgment. The working lead and workers propagate the preference
internally without an echo. A directly speaking agent without a separate front
retains its explicitly assigned presentation contract. Pending results remain
pending until presented; no replay, inferred approval or work cancellation follows.

Mailbox wording must match AgentVoice's retained workspace-session controller:
entries and cached openings survive frontend detach and runtime replacement;
explicit new_session or server shutdown clears them. Replacement interrupts native
work and rebuilds inventory, without replaying old wakes. The worker's native mode
remains within 1,600 UTF-8 bytes. This corrects wording, not runtime behavior.

These are instructions, not a shared semantic hold latch, output gate or exactly-once
speech guarantee. Resource sync prepares source/installed bytes without reloading
calls or independent workspace role snapshots. Loaded behavior and the historical
mute-click report remain separate human qualification; no runtime restart, model
change, new UI or automatic HUD mutation is part of this decision.

## September 14 clarification: distinct brief acknowledgments

The human requested that a conversational hold be acknowledged as “On hold,”
not “Muted.” The speech owner uses “On hold” / “Off hold” for hold and
“Muted” / “Unmuted” for conversational mute. Both role speech appends and the
manager's directly owned speech fallback use this distinction. A separate
working backend remains silent; authorized work and internal reporting continue.
Physical audio commands/status and ambiguous bare terms retain their existing
boundaries. This changes authored speech guidance only, without physical audio
code, a runtime hold state or a call restart. Live spoken behavior still needs
observation after the relevant prompt-loading boundary.
