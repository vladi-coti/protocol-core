---
id: privacy-P3-M-47
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-47
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-47: Plain liquidation detail fields stay stale after encrypted writes — Do legacy plaintext deficit/fee fields show zero while encrypted nonzero?

## Auditor claim

Medium severity. See [report §M-47](../report.md).

## Code references

`AccountStorage.sol:29,34; LiquidationFacetImpl.sol:128,133`

## Suggested test seam

getLiquidatedStateOfPartyA after liquidation

## Auditor recommendation

Remove stale fields or sync explicitly

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

**One-liner:** `getLiquidatedStateOfPartyA` returns `ViewLiquidationDetail` without plaintext husks; use encrypted deficit/fee getters.

Confirmed: storage `LiquidationDetail.deficit` / `liquidationFee` / `partyAAccumulatedUpnl` always written `0`; real values in `encryptedLiquidationDeficit` / `encryptedLiquidationFee`. Syncing husks would re-leak amounts.

**Fix:**
- Keep husks in storage struct (layout) with NatSpec.
- Add `ViewLiquidationDetail` (no husks).
- `getLiquidatedStateOfPartyA` returns the view type.

**Files:** `AccountStorage.sol`, `IViewFacet.sol`, `ViewFacet.sol`  
**Regression:** `test/audit/M47.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M47.test.ts --grep "M-47"
```
