---
id: privacy-P3-M-16
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-16
severity: Medium
status: open
blocks: design-M-16-liquidation-type-disclosure
blocked_by: design-M-16-liquidation-type-disclosure
report: ../report.md
---

## Question

M-16: Public liquidation type leaks private deficit range — Does public LiquidationType reveal deficit bucket?

## Auditor claim

Medium severity. See [report §M-16](../report.md).

## Code references

`LiquidationFacetImpl.sol:169,170; DeferredLiquidationFacetImpl.sol:109,110`

## Suggested test seam

Read liquidation type after liquidation — infer range

## Auditor recommendation

See design-M-16 for intentional vs bug

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
