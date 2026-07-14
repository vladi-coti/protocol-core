---
id: logic-P0-H-38
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-38
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-38: Zero-CVA liquidations can select LATE and divide by zero — Can zero-CVA PartyA liquidation hit LATE branch and divide by zero?

## Auditor claim

High severity. See [report §H-38](../report.md).

## Code references

`PartyAFacetImpl.sol:78,81; LiquidationFacetImpl.sol:167,171,300,301`

## Suggested test seam

`test/audit/H38.test.ts` — zero-CVA positions, deficit == LF

## Auditor recommendation

Disallow zero-CVA in liquidation path or add zero-CVA branch

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: valid. Disposition: implement.**

- `sendQuote` has no `cva > 0` require.
- Classification: `NORMAL` if deficit < LF; `LATE` if deficit ≤ LF+CVA. With CVA=0 → `LATE` iff deficit == LF.
- LATE settlement divided by `totalCva` with no zero guard → revert.

**Red (pre-fix, Muon disabled):**

```bash
python3 utils/update_sig_checks.py 1
npx hardhat test --network coti-testnet test/audit/H38.test.ts
# ✔ accepts zero-CVA quote (control)
# ✔ LATE + zero total CVA reverts on liquidatePositions (div by zero)
# 2 passing (~14m)
```

**Fix:** `LiquidationFacetImpl.liquidatePositionsPartyA` LATE branch — if `totalCva == 0`, use `adjustedCva = quoteCva` (no div). Knife-edge LATE (deficit==LF) already stores deficit=0; with zero CVA all quote CVAs are 0.

**Green (post-fix):**

```bash
python3 utils/update_sig_checks.py 1
npx hardhat test --network coti-testnet test/audit/H38.test.ts --grep "without div-by-zero"
# ✔ H-38: LATE + zero total CVA liquidates without div-by-zero (~7m)
python3 utils/update_sig_checks.py 0
```

**Regression:** `test/audit/H38.test.ts` — `H-38: LATE + zero total CVA liquidates without div-by-zero`

**Not changed:** quote-entry `cva > 0` policy (product); deferred classification twin (same LATE path via `LiquidationFacetImpl`).
