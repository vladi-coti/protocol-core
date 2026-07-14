---
id: privacy-P1-H-11
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-11
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-11: Settlement events publish encrypted opened prices in plaintext — Does SettleUpnl event include plaintext updatedPrices?

## Auditor claim

High severity. See [report §H-11](../report.md).

## Code references

`SettlementFacetEvents.sol:11,13; SettlementFacet.sol:38,40`

## Suggested test seam

test/Settlement.behavior.ts — inspect SettleUpnl logs

## Auditor recommendation

Remove plaintext prices from event

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
