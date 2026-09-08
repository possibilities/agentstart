# Retirement checks current contracts

Historical record restored September 8, 2026. The Pi migration is complete
and its execution machinery has been removed. The original validation
rationale follows; it does not add a migration phase to current installers.

Pi cleanup verifies the installed tools’ current Pi-free behavior and source, their installation identity, and ownership of the state being removed; it does not pin historical retirement commits.
A historical SHA cannot establish that a newer installed tool preserves retirement, and requiring a frozen upstream tip breaks ordinary installation after unrelated updates.
Current Git provenance and deployed receipts remain integrity checks, while command contracts and the existing pre-deletion and final audits decide whether cleanup may proceed.
