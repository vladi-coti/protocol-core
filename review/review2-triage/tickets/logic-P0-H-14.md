---
id: logic-P0-H-14
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-14
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-14: Force-close liquidation ignores reserve credit when computing PartyB deficit — Does PartyB liquidation use pre-reserve available balance after reserve credit applied?

## Auditor claim

High severity. See [report §H-14](../report.md).

## Code references

`ForceActionsFacetImpl.sol:160,185,208,213,219; LibLiquidation.sol:49,55`

## Suggested test seam

test/ForceClosePosition.behavior.ts — insolvent PartyB with partial reserve

## Auditor recommendation

Recompute available balance after reserve credit

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [x] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`.** Force-close third branch zeros reserve and credits it into PartyB allocated, then called `liquidatePartyBFromAvailable(..., gtPartyBAvailableBalance)` — the **pre-reserve** available. Deficit / remaining LF / liquidator tip used a stale snapshot.

**Fix disposition: `implement`** — **landed:** pass `gtWithReserve` (available + reserve, still negative) into `liquidatePartyBFromAvailable`.

**Evidence (sim)**

```bash
python3 utils/update_sig_checks.py 1
# sim: cd /Users/Vlad1/coti/sim-coti-node && npm start
TEST_MODE=static npx hardhat test test/audit/H14.test.ts --grep 'H-14' --network localSimCoti
```

- Pre-fix red: PartyA gain delta vs no-reserve ≈ **R** (overpays full reserve).
- Post-fix green: delta ≈ **R × liquidatorShare** (0.1 with fixture share).

**Implement brief (done)**

- `ForceActionsFacetImpl.sol`: `liquidatePartyBFromAvailable(..., gtWithReserve, ...)`.
- Regression: `test/audit/H14.test.ts` / `H14.behavior.ts`.
