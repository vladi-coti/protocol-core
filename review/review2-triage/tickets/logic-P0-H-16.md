---
id: logic-P0-H-16
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-16
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-16: Deferred liquidation type uses current balance not signed snapshot — Can balance change between snapshot and execution alter liquidation type? (Check review1#4 fix status)

## Auditor claim

High severity. See [report §H-16](../report.md).

## Code references

`MuonStorage.sol:67,72; DeferredLiquidationFacetImpl.sol:39,41,49,52`

## Suggested test seam

Deferred liquidation test with balance mutation between sign and execute

## Auditor recommendation

Use signed snapshot for type and accounting consistently

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** Review1#4-style snapshot overload already existed (`partyAAvailableBalanceForLiquidation(upnl, allocatedBalance, partyA)`), but deferred path still re-read **current** allocated for reimbursement + NORMAL/LATE/OVERDUE after proving insolvency from `liquidationSig.liquidationAllocatedBalance`.

Post-sign `allocate` can flip type (fixture: OVERDUE→NORMAL) while signature still authenticates the old snapshot.

**Fix:** reuse signed snapshot for both reimbursement availability and `deferredSetSymbolsPrice` classification (`DeferredLiquidationFacetImpl.sol`).

**Evidence**

- Red (pre-fix): type became `NORMAL` (1) vs snapshot `OVERDUE` (3)
- Green (post-fix): `test/audit/H16.test.ts --grep H-16` pass on `localSimCoti` + `coti-testnet`

**Regression:** `test/audit/H16.test.ts` / `H16.behavior.ts`
