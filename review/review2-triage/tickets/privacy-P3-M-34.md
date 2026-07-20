---
id: privacy-P3-M-34
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-34
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-34: Balance-change event types leak PnL direction — Does REALIZED_PNL_IN vs OUT branch leak direction?

## Auditor claim

Medium severity. See [report §M-34](../report.md).

## Code references

`LibQuote.sol:262; LibSettlement.sol:124; LiquidationFacetImpl.sol:422`

## Suggested test seam

Settlement/liquidation event type inspection

## Auditor recommendation

Constant event shape like normal close path

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement` (done)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict:** `valid`  
**Disposition:** `implement` (done)

**One-liner:** settle/liq branched on PnL sign for events; now dual-emit IN+OUT like LibQuote close (one encrypted zero).

Confirmed:
- `LibQuote` close already constant-shape (both IN+OUT via `mux`).
- Pre-fix `LibSettlement` / PartyA liq settle emitted only the matching type → public direction leak.
- Red: settle mark-down LONG → only `PartyB:IN` + `PartyA:OUT`.

**Fix:** always emit both `REALIZED_PNL_IN` and `REALIZED_PNL_OUT` on settlement and liquidation PartyB settle paths; unused arm is encrypted zero.

**Residual:** balance updates still `decrypt` for add/sub control flow — event metadata fixed; full branch-free settle is larger follow-up.

**Files:** `LibSettlement.sol`, `LiquidationFacetImpl.sol`  
**Regression:** `test/audit/M34.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M34.test.ts --grep "M-34"
# 3 passing
```
