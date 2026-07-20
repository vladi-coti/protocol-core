---
id: logic-P3-L-06
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-06
severity: Low
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-06: PartyB-filtered position views scan wrong range — Do PartyB position views return sparse default structs?

## Auditor claim

Low severity. See [report §L-06](../report.md).

## Code references

`ViewFacet.sol` PartyB-filtered position views

## Suggested test seam

PartyB position view with non-dense quote IDs

## Auditor recommendation

Page actual quote IDs, return compact arrays

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

PartyB-filtered views treated `start`/`size` as a quote-id window but always returned `new ViewQuote[](size)` padded with empty defaults. Missed positions past the window were a separate pagination footgun; padded empties misled consumers.

**Fix:** `_getPositionsFilteredByPartyB` clamps the id window to `lastId` and returns a compact array of matches only (all / open / active × user/observer).

**Regression:** `test/audit/L06.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/L06.test.ts --grep "L-06"
```

Sim: 2 passing (previously length 100 with empties).
