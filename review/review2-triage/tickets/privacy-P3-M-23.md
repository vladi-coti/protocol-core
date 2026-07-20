---
id: privacy-P3-M-23
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-23
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-23: Observer events missing for partial-fill child quotes — Does partial fill omit observer child quote event?

## Auditor claim

Medium severity. See [report §M-23](../report.md).

## Code references

`PartyBGroupActionsFacetImpl.sol:61,96` (now `PartyBGroupActionsFacet.sol` / `PartyBPositionActionsFacet.sol`)

## Suggested test seam

Partial fill flow — compare party events vs observer events

## Auditor recommendation

Emit observer child quote event on partial fill

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief — see Answer

## Answer

**Verdict:** `valid`  
**Disposition:** `implement`

Partial fill creates a child quote and emits `SendQuoteForPartyA` / `SendQuoteForPartyB`, but skipped `ObserverSendQuote` that `sendQuote` emits. Observer storage for the child was already written via `LibEncryption.storeQuote*`; only the event stream was incomplete.

**Fix:** emit `ObserverSendQuote` (partyB=`address(0)` + each whitelist partyB) alongside child `SendQuote*` in `PartyBPositionActionsFacet` and `PartyBGroupActionsFacet`. Moved `ObserverSendQuote` to `IPartiesEvents` so PartyB facets can emit it.

**Regression:** `test/audit/M23.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M23.test.ts --grep "M-23"
```

Sim: 2 passing after fix (previously no `ObserverSendQuote` for child).
