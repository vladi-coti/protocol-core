---
id: logic-P2-M-02
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-02
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-02: Same-timestamp old liquidation prices can be reused — Can later liquidation reuse stale symbol prices with same timestamp?

## Auditor claim

Medium severity. See [report §M-02](../report.md).

## Code references

`AccountStorage.sol:43,45; LiquidationFacetImpl.sol:156,254,502,509`

## Suggested test seam

Liquidation test with repeated timestamp

## Auditor recommendation

Bind prices to liquidation id or clear on cleanup

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement` (done)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

`symbolsPrices[partyA][symbolId]` stores `{price, timestamp}` only. `liquidatePositionsPartyA` required `timestamp == liquidationDetails.timestamp`. Settle cleanup clears status/type/fees but **not** `symbolsPrices`. A later `liquidatePartyA` with a **new** `liquidationId` but the **same** Muon timestamp could skip `setSymbolsPrice` and still pass the check, settling with the leftover price.

**Fix:** bind each stored price to `keccak256(liquidationId)` via `AccountStorage.symbolPriceLiquidationId` (appended mapping). Set in `setSymbolsPrice` (normal + deferred). Positions require timestamp **and** matching liquidationId hash.

**Regression:** `test/audit/M02.test.ts` — static bind check + live: after full liq cleanup, second liq with reused timestamp without `setSymbolsPrice` reverts `Price should be set`.

```bash
npx hardhat test --network localSimCoti test/audit/M02.test.ts
# sim: 2/2 PASS
```
