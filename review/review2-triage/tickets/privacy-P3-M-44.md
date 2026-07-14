---
id: privacy-P3-M-44
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-44
severity: Medium
status: open
blocks: design-M-13-observer-rotation (soft)
blocked_by: design-M-13-observer-rotation
report: ../report.md
---

## Question

M-44: Liquidation cleanup leaves observer ciphertext stale — Does cleanup clear primary state but not observer copies?

## Auditor claim

Medium severity. See [report §M-44](../report.md).

## Code references

`LiquidationFacetImpl.sol:202,204,503; ViewFacet.sol:153,174`

## Suggested test seam

Post-liquidation observer view vs primary state

## Auditor recommendation

Use observer-aware cleanup helpers

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
