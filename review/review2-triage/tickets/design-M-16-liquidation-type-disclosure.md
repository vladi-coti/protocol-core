---
id: design-M-16-liquidation-type-disclosure
labels: [group:design-product, wayfinder:grilling]
priority: P2
finding: M-16
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-16: Decide liquidation type disclosure policy — Is public LiquidationType intentional lifecycle disclosure?

## Auditor claim

Medium severity. See [report §M-16](../report.md).

## Code references

`LiquidationFacetImpl.sol:169,170`

## Suggested test seam

N/A — grilling session

## Auditor recommendation

Accept public type or redesign classification

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
