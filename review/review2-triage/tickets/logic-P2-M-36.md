---
id: logic-P2-M-36
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-36
severity: Medium
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-36: Deferred liquidation reimbursement underflow — Does positive UPNL make reimbursement subtraction underflow?

## Auditor claim

Medium severity. See [report §M-36](../report.md).

## Code references

`DeferredLiquidationFacetImpl.sol:49,53; LibAccount.sol:122,124`

## Suggested test seam

Deferred liquidation with availability > allocated

## Auditor recommendation

Cap reimbursement to allocated collateral

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `invalid`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict:** `invalid` (superseded by [H-16](logic-P0-H-16.md))  
**Disposition:** `wontfix`

### Why

Auditor path: prove insolvency from signed snapshot, then reimburse using **current** `available = allocated − locks + UPNL`. When UPNL is large, `available` can exceed **current** allocated → `checkedSub` underflows.

After H-16, insolvency **and** the reimbursement gate share one snapshot-based `gtLiquidationAvailableBalance`:

1. `require(available < 0)` (must be insolvent)
2. `if (available > 0) { currentAllocated.checkedSub(available); … }`

Same value cannot be both `< 0` and `> 0`. Positive-reimbursement / underflow branch is **dead**. No separate fix.

Optional hygiene (not required for this ticket): delete the dead `if (gtAvailableBalance.gt(gtZero))` block.

### Evidence

```bash
npx hardhat test --network localSimCoti test/audit/M36.test.ts --grep "M-36"
# 1 passing — static: snapshot available + lt(0) before gt(0) reimburse; no current-alloc recompute
```
