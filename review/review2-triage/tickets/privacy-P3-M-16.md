---
id: privacy-P3-M-16
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-16
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: design-M-16-liquidation-type-disclosure
report: ../report.md
---

## Question

M-16: Public liquidation type leaks private deficit range — Does public LiquidationType reveal deficit bucket?

## Auditor claim

Medium severity. See [report §M-16](../report.md).

## Code references

`LiquidationFacetImpl.sol`; `DeferredLiquidationFacetImpl.sol`; `AccountStorage.LiquidationDetail`

## Suggested test seam

Read liquidation type after liquidation — infer range

## Auditor recommendation

See design-M-16 for intentional vs bug

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Design decision: [design-M-16](design-M-16-liquidation-type-disclosure.md) — keep public
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] Regression documents intentional public type

## Answer

**Verdict:** `design-choice`  
**Disposition:** `wontfix`

Confirmed leak shape: decrypting deficit vs LF / LF+CVA writes public `LiquidationType`. Exact deficit remains encrypted; bucket is intentional.

No code change. Policy: [design-M-16](design-M-16-liquidation-type-disclosure.md).

**Regression:** `test/audit/M16.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M16.test.ts --grep "M-16"
```
