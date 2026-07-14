---
id: privacy-P3-M-47
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-47
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-47: Plain liquidation detail fields stay stale after encrypted writes — Do legacy plaintext deficit/fee fields show zero while encrypted nonzero?

## Auditor claim

Medium severity. See [report §M-47](../report.md).

## Code references

`AccountStorage.sol:29,34; LiquidationFacetImpl.sol:128,133`

## Suggested test seam

getLiquidatedStateOfPartyA after liquidation

## Auditor recommendation

Remove stale fields or sync explicitly

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
