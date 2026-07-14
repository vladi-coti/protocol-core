---
id: logic-P0-H-38
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-38
severity: High
status: in-progress
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

test/LiquidationFacet.behavior.ts — zero-CVA positions, deficit == LF

## Auditor recommendation

Disallow zero-CVA in liquidation path or add zero-CVA branch

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(in progress)*

**Code path: valid on paper**

- `sendQuote` has no `cva > 0` require.
- Classification: `NORMAL` if deficit < LF; `LATE` if deficit ≤ LF+CVA. With CVA=0 → `LATE` iff deficit == LF.
- LATE settlement: `gtQuoteCva.checkedMul(gtDeficit).div(gtTotalCva)` with no zero-CVA guard.

**Test blocker (resolved 2026-07-13)**

Was not COTI `setPublic256(0)` / offBoard. Two real blockers:

1. **Muon checks restored** while tests still use dummy `sigs.signature = 0` → `LibMuonV04ClientBase` reverts `no zero inputs allowed` after balance checks pass. Unaffordable C-01/H-02 paths never reached verify. Fix for testnet: `python3 utils/update_sig_checks.py 1` (same as `utils/runTests.sh`).
2. **Diamond library deploy OOG** at hardcoded 30M gas (`PartyBGroupActionsFacetImpl` ~25kB). `tasks/deploy/diamond.ts` now uses `gasOptions` (60M); `coti-testnet` `blockGasLimit` raised to 60M.

Verified:

```bash
TEST_MODE=static npx hardhat test test/PrivateVariables.test.ts --grep "Should successfully send a long"
# ✔ quoteId 1, 1 passing (~6m)
```

**Next**

1. Write `test/audit/H38.test.ts` (zero-CVA → LATE at deficit==LF).
2. Run red test on testnet; record output.
3. Implement LATE zero-CVA guard (or classification fix).
