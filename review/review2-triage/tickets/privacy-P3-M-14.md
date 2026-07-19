---
id: privacy-P3-M-14
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-14
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: design-M-13-observer-rotation
report: ../report.md
---

## Question

M-14: Observer balance-change events missing for non-accounting mutations — Do fee/PnL/liquidation balance mutations skip observer events?

## Auditor claim

Medium severity. See [report §M-14](../report.md).

## Code references

`SharedEvents.sol:29,31; LibQuote.sol:253,263`

## Suggested test seam

Compare storage mutations vs observer event emission

## Auditor recommendation

Emit observer events for all encrypted balance mutations

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `wontfix` (design-choice)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `wontfix` (design-choice — require polling).**

Claim confirmed:
- `ObserverBalanceChangePartyA/B` only emitted from `AccountFacet` allocate/deallocate (9 emit sites).
- PnL/fee/liquidation paths emit user `BalanceChange*` only (`LibQuote`, `LibSettlement`, `LiquidationFacetImpl`, etc.) — 37 user emits vs 9 observer.
- Observer **storage** still updates via `LibEncryption.storePartyAAllocatedBalance` / PartyB helpers on those paths.

So event-only observer indexers miss material mutations; view/polling observers do not.

Auditor offered two fixes: emit everywhere **or** require polling. Align with M-13 (observer views + migration): **polling / view reads are the source of truth**. Full dual-event emission on every PnL/liq path is gas-expensive theater unless product commits to an event-sourced observer indexer.

**Regression (documents gap, stays green under wontfix):** `test/audit/M14.test.ts` — static emit-site check + fillClose: user PnL events present, no ObserverBalanceChange, observer allocated storage still moves.

```bash
npx hardhat test --network localSimCoti test/audit/M14.test.ts
# sim: 2/2 PASS
```

If product later wants event-sourced observers, reopen as implement: mirror every `BalanceChange*` with `ObserverBalanceChange*` using `observerAllocatedBalances` / PartyB observer slots (same pattern as AccountFacet).
