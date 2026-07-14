---
id: privacy-P3-M-25
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-25
severity: Medium
status: open
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

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
