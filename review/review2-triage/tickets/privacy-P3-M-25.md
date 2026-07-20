---
id: privacy-P3-M-25
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-25
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-25: Encrypted balance-change events mix deltas and snapshots — Do allocation events use snapshot while settlement uses delta?

## Auditor claim

Medium severity. See [report §M-25](../report.md).

## Code references

`SharedEvents.sol:25,27; AccountFacet.sol:53,56; LibSettlement.sol:126,137`

## Suggested test seam

Indexer simulation — miscompute if all treated as deltas

## Auditor recommendation

Split event types or add semantic field

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix` (NatSpec only; no ABI split)
- [x] If valid: write implement brief — N/A

## Answer

**Verdict:** `design-choice`  
**Disposition:** `wontfix` (document semantics; keep one event shape)

**One-liner:** `BalanceChangeType` already keys amount meaning — ALLOCATE/DEALLOCATE = snapshot, else = delta.

Claim confirmed:
- `AccountFacet.allocate/deallocate` emit post-`allocatedBalances` ciphertext under `ALLOCATE`/`DEALLOCATE`.
- `LibSettlement` / close PnL paths emit `offBoardToUser(gtAmount)` deltas under `REALIZED_PNL_*`.
- Runtime: second allocate of 300 after 500 → event amount decrypts to **800** (snapshot), not 300.
- Runtime: fillClose PnL event amount equals allocated **delta**, not post-balance.

Not a privacy leak (ciphertexts stay encrypted). It is an indexer schema footgun if consumers ignore `_type`.

Reject ABI split / extra semantic field: plaintext allocate size already on `AllocatePartyA`/`DeallocatePartyA`; encrypted snapshot on BalanceChange is useful for ciphertext sync. Consumers must branch on `_type`.

NatSpec added on `SharedEvents` BalanceChange events. Note: PartyA liquidation cleanup can emit `REALIZED_PNL_OUT` with a pre-wipe allocated snapshot — type-name exception; indexers of that path should treat carefully (or poll views).

**Regression:** `test/audit/M25.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M25.test.ts --grep "M-25"
# 3 passing
```
