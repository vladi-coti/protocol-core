---
id: logic-P2-M-03
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-03
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-03: Liquidation dispute accumulator ignores CVA released at settlement — Does dispute check false-positive when CVA release omitted?

## Auditor claim

Medium severity. See [report §M-03](../report.md).

## Code references

`LiquidationFacetImpl.sol:88,90,95,99,414,416`

## Suggested test seam

Liquidation dispute scenario with CVA release

## Auditor recommendation

Include CVA in accumulator formula

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement` (done)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

`_updateLiquidationAccumulator` capped positive PartyB `expectedAmount` at `partyBAllocated` only. `settlePartyALiquidation` adds `settlementStates.cva` to PartyB **before** applying PnL, so payable capacity is `allocated + cva`. When `allocated < expected <= allocated+cva`, the accumulator under-counts the winning leg → `accumulated != upnl` → false `disputed`, blocking settle even though settle would pay in full.

**Fix:** positive-leg cap uses `gtPayable = allocated + settlementCva` (same order as settle).

**Regression:** `test/audit/M03.test.ts` — static CVA-in-cap check + two-hedger live (loss vs win PartyB, profit in `(alloc, alloc+cva]` → not disputed).

```bash
npx hardhat test --network localSimCoti test/audit/M03.test.ts --grep 'M-03'
# sim: 2/2 PASS (red before fix: disputed==true; green after: disputed==false)
```
