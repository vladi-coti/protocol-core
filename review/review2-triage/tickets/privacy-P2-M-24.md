---
id: privacy-P2-M-24
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: M-24
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-24: Emergency close emits close price as plaintext — Is emergency close price public in event while other closes encrypted?

## Auditor claim

Medium severity. See [report §M-24](../report.md).

## Code references

`IPartyBPositionActionsEvents.sol:12,17; RecoveryActionsFacet.sol:39,45`

## Suggested test seam

test/EmergencyClosePosition.behavior.ts — event inspection

## Auditor recommendation

Encrypt event or document emergency as public-price

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
