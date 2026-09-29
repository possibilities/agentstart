# 0050: Serialize Devin snapshot registration and reaping

Accepted September 28, 2026. Strengthens [ADR 0048](0048-share-devin-snapshots-across-concurrent-sessions.md)'s shared-snapshot cleanup decision.

The cleanup service previously scanned invocation records, checked that their
processes had ended, then deleted the snapshot. A new wrapper could join that
snapshot after the scan but before deletion, leaving its live session without
Role resources. A second scan cannot close this gap.

Snapshot creation/registration and cleanup now use the same advisory lock per
real Git root. Cleanup re-reads that root's records while holding the lock and
deletes only when none of its wrapper or child identities is live. A new launch
either joins before the locked check or waits and creates a fresh snapshot
after cleanup. Lock files live in the private invocation-state directory and
are never unlinked: replacing a lock inode would defeat mutual exclusion.
