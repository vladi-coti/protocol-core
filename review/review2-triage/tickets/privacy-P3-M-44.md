---
id: privacy-P3-M-44
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-44
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: design-M-13-observer-rotation
report: ../report.md
---

## Question

M-44: Liquidation cleanup leaves observer ciphertext stale — Does cleanup clear primary state but not observer copies?

## Auditor claim

Medium severity. See [report §M-44](../report.md).

## Code references

`LiquidationFacetImpl.sol:202,204,503; ViewFacet.sol:153,174`

## Suggested test seam

Post-liquidation observer view vs primary state

## Auditor recommendation

Use observer-aware cleanup helpers

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement`.**

In `liquidatePendingPositionsPartyA`, locked PartyB pending quotes are zeroed with a direct assign:

```solidity
accountLayout.partyBPendingLockedBalances[quote.partyB][partyA] = gtZeroLockedB.offBoard(partyBEncryptionAddress);
```

That skips `LibEncryption.storePartyBPendingLockedBalance`, which also updates `observerPartyBPendingLockedBalances`. PartyA pending correctly uses `storePartyAPendingLockedBalance`. After cleanup, primary pending is 0 while observer pending still decrypts to the pre-liq CVA/LF/MM.

**Regression (green after fix):** `test/audit/M44.test.ts` — static store-helper check + live: after `liquidatePendingPositionsPartyA`, PartyB pending locked = 0 **and** observer pending CVA = 0.

```bash
npx hardhat test --network localSimCoti test/audit/M44.test.ts
# sim: 2/2 PASS
```

### Fix landed

Replace direct `offBoard` assign with `LibEncryption.storePartyBPendingLockedBalance(accountLayout, quote.partyB, partyA, gtZeroLockedB)` in `LiquidationFacetImpl.liquidatePendingPositionsPartyA`.
