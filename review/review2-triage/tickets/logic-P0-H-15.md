---
id: logic-P0-H-15
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-15
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-15: PartyB liquidation reverts when remaining LF exceeds allocated balance — Can insolvent PartyB with positive UPNL cause LF subtraction revert?

## Auditor claim

High severity. See [report §H-15](../report.md).

## Code references

`LibAccount.sol:225,232; LibLiquidation.sol:49,55,96,97`

## Suggested test seam

test/LiquidationFacet.behavior.ts — positive UPNL, LF > allocated

## Auditor recommendation

Cap remaining LF to payable allocated balance

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** `partyBAvailableBalanceForLiquidation = alloc - (cva+lf) + upnl` can be negative while `remainingLf = lf - deficit = alloc - cva + upnl` exceeds `alloc` whenever `upnl > cva` and `lf > alloc`. Then `partyBAllocated.checkedSub(remainingLf)` reverts (`overflow error`), so insolvent PartyB cannot be liquidated.

**Fix:** Cap `remainingLf` with `MpcCore.min(remainingLf, partyBAllocated)` before share split and before the subtract (`LibLiquidation.sol`).

**Evidence**

- Red (pre-fix): `TEST_MODE=static npx hardhat test test/audit/H15.test.ts --grep 'H-15' --network localSimCoti` → `overflow error` on `liquidatePartyB`
- Green (post-fix): same command → pass on sim + `coti-testnet`; liquidation completes, `isPartyBLiquidated=true`, PartyB alloc=0
- Fixture: high-LF open + `deallocateForPartyB` under inflated dummy +UPNL to leave `lf > alloc`, then liquidate with `upnl = cva+1`

**Regression:** `test/audit/H15.test.ts` / `H15.behavior.ts`
