---
id: logic-P0-H-12
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-12
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-12: settleAndForceClosePosition settles against caller not quote PartyA — Does third-party caller cause settlement to check wrong PartyA?

## Auditor claim

High severity. See [report §H-12](../report.md).

## Code references

`SettleAndForceCloseFacet.sol:26; ForceActionsFacetImpl.sol:179,180; LibSettlement.sol:53`

## Suggested test seam

test/SettleAndForceClosePosition.behavior.ts — third party force-close with settlement

## Auditor recommendation

Pass quote.partyA into settlement or restrict to PartyA

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [x] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`.** Pre-fix: third-party `settleAndForceClosePosition` with settlement data reverted `LibSettlement: PartyA is invalid` because settlement used `msg.sender` as PartyA.

**Fix disposition: `implement`** — **landed:** pass `quote.partyA` into `LibSettlement.settleUpnl` + `SettleUpnl` event / allocated-balance lookup in `SettleAndForceCloseFacet`.

**Evidence (sim)**

```bash
python3 utils/update_sig_checks.py 1
# sim node: cd /Users/Vlad1/coti/sim-coti-node && npm start
TEST_MODE=static npx hardhat test test/audit/H12.test.ts --grep 'third-party caller' --network localSimCoti
```

Post-fix: third-party closes quote on `localSimCoti`.

Sim↔testnet agreement (speed check only): [`../test-runs/sim-vs-testnet.md`](../test-runs/sim-vs-testnet.md).

**Implement brief (done)**

- `ForceActionsFacetImpl.sol`: both `settleUpnl(..., quote.partyA, true)`.
- `SettleAndForceCloseFacet.sol`: emit + balance ciphertext from `quote.partyA`.
- Regression: `test/audit/H12.test.ts` — third-party expects `CLOSED`.
