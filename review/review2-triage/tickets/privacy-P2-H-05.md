---
id: privacy-P2-H-05
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: H-05
severity: High
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-05: PartyA liquidation exposes plaintext risk snapshots — Are UPNL/unrealized loss plaintext in LiquidationDetail? (Check report5#3 partial fix)

## Auditor claim

High severity. See [report §H-05](../report.md).

## Code references

`AccountStorage.sol:29,32; LiquidationFacetImpl.sol:128,131`

## Suggested test seam

Liquidation tx + getLiquidatedStateOfPartyA inspection

## Auditor recommendation

Remove plaintext fields or encrypt

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `invalid`
- [x] Fix disposition: `wontfix` (already fixed; residual husks → M-47)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `invalid`. Disposition: `wontfix`.**

Report claim is stale. `LiquidationDetail.upnl` and `totalUnrealizedLoss` are `utInt256`, written via `LibEncryption.offBoardToUser` in both normal and deferred `liquidatePartyA` (matches H-01 checklist). `getLiquidatedStateOfPartyA` returns ciphertext; PartyA decrypts a nonzero risk value, a stranger does not recover the same plaintext.

Leftover plaintext husks (`deficit`, `liquidationFee`, `partyAAccumulatedUpnl` always 0) are **M-47**, not the H-05 risk-snapshot claim. `liquidationType` disclosure is **M-16**. Public Muon/mark prices under H-01 path C are intentional.

**Regression:** `test/audit/H05.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/H05.test.ts --grep 'H-05'
# sim: 2/2 PASS
```
