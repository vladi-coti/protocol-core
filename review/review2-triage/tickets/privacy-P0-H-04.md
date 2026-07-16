---
id: privacy-P0-H-04
labels: [group:privacy-leak, wayfinder:research]
priority: P0
finding: H-04
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-04: Force-close price checks run before Muon signature verification — Can invalid Muon sig + chosen prices oracle encrypted close price via revert order?

## Auditor claim

High severity. See [report §H-04](../report.md).

## Code references

`ForceActionsFacetImpl.sol:88,105; LibMuonForceActions.sol:12,39`

## Suggested test seam

Force close with bad sig, vary prices, observe revert point

## Auditor recommendation

Verify Muon sig before decrypting price predicates

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** `forceClosePosition` onboarded/decrypted `requestedClosePrice` gap predicates and branched on revert *before* `LibMuonForceActions.verifyHighLowPrice`. Junk Muon + probing `lowest`/`highest` yields `"Requested close price not reached"` vs success past that check → oracle on encrypted close threshold.

**Evidence (sim, Muon audit-off)**

```bash
TEST_MODE=static npx hardhat test test/audit/H04.test.ts --grep 'H-04' --network localSimCoti
```

- Behavioral: too-high `lowest` on SHORT → early revert; valid `lowest` → close succeeds (same junk sig).
- Source-order red→green: `verifyHighLowPrice` must precede `requestedClosePrice.ciphertext` onboard.

**Fix:** call `verifyHighLowPrice` (+ settlement verify when used) immediately after public requires, before private price onboard/decrypt.

**Regression:** `test/audit/H04.test.ts` / `H04.behavior.ts`

Note: with audit Muon disabled, verify is a no-op so the behavioral price oracle still exists in test mode; production Muon-on makes unauthenticated probes fail at verify first.
