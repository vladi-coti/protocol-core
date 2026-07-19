---
id: privacy-P1-H-11
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-11
severity: High
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-11: Settlement events publish encrypted opened prices in plaintext — Does SettleUpnl event include plaintext updatedPrices?

## Auditor claim

High severity. See [report §H-11](../report.md).

## Code references

`SettlementFacetEvents.sol:11,13; SettlementFacet.sol:38,40`

## Suggested test seam

test/Settlement.behavior.ts — inspect SettleUpnl logs

## Auditor recommendation

Remove plaintext prices from event

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

`SettleUpnl` rebroadcast `updatedPrices` (values written into encrypted `openedPrice`) as `uint256[]` in the permanent log. Unlike H-13 free-collateral theater, this is trading-state disclosure.

**Fix:** drop `updatedPrices` from `SettleUpnl` in `SettlementFacetEvents`, `SettlementFacet`, and `SettleAndForceCloseFacet`. Calldata of `settleUpnl` still carries plaintext args (inherent to current public ABI) — documented as residual, not event-amplified.

**Regression:** `test/audit/H11.test.ts` — ABI static check + live SettleUpnl decode (stale ABI with `updatedPrices` must not parse). Sim: 2/2 PASS.

```bash
TEST_MODE=static npx hardhat test --network localSimCoti test/audit/H11.test.ts
```
