---
id: logic-P2-M-15
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-15
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-15: priceValidTime configured but not enforced — Is priceValidTime ignored on price-bearing Muon paths?

## Auditor claim

Medium severity. See [report §M-15](../report.md).

## Code references

`MuonStorage.sol:139,140; LibMuonPartyA.sol:15; LibMuonPartyB.sol:13`

## Suggested test seam

Muon signature test with stale price outside priceValidTime

## Auditor recommendation

Enforce priceValidTime everywhere or remove setting

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement` (done)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

`priceValidTime` was stored but never read; paths used `upnlValidTime` (or none). Under H-01 path C, Muon only signs prices — dual windows on one timestamp is nonsense.

**Fix:** sole freshness knob is `priceValidTime` on Muon verify + liquidate/deferred liquidate. `upnlValidTime` kept in storage/`setMuonConfig` ABI but unused for acceptance.

**Regression:** `test/audit/M15.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M15.test.ts --grep 'M-15'
```
