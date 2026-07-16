---
id: logic-P0-H-26
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-26
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-26: Force-close PartyB liquidation uses post-close balance without closing quote — Does liquidation use post-close availability while quote still open in storage?

## Auditor claim

High severity. See [report §H-26](../report.md).

## Code references

`ForceActionsFacetImpl.sol:160,178; LibSolvency.sol:183,186; LibLiquidation.sol:49,55`

## Suggested test seam

test/ForceClosePosition.behavior.ts — PartyB insolvent on simulated close

## Auditor recommendation

Close quote before liquidation or use consistent pre-close state

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** Force-close insolvency branch computes available via `getAvailableBalanceAndPartyBUpnlAfterClosePosition` (unlocks closing quote’s cva+lf into the number) then calls `liquidatePartyBFromAvailable` while the quote stays `CLOSE_PENDING` and `partyBLockedBalances.lf` still includes that LF. `closeQuote` cannot run first (`Insufficient PnL balance` when PartyB would go negative).

**Evidence (sim)**

```bash
python3 utils/update_sig_checks.py 1
# sim up on :8546
TEST_MODE=static npx hardhat test test/audit/H26.test.ts --grep 'H-26' --network localSimCoti
```

- Red: `remainingLf=50.5e18` vs `lfAfterUnlock=3e18` (closed quote `lf=50e18` still counted).
- Green (post-fix): same grep passes on `localSimCoti` + `coti-testnet`; H-14 still green.

**Fix:** before `liquidatePartyBFromAvailable`, subtract the closing quote’s proportional cva+lf from `partyBLockedBalances` only (quote stays open for `liquidatePositionsPartyB`; PartyA locks untouched to avoid double-`subQuote`).

**Regression:** `test/audit/H26.test.ts` / `H26.behavior.ts`
