---
id: privacy-P0-H-08
labels: [group:privacy-leak, wayfinder:research]
priority: P0
finding: H-08
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-08: Account balance checks expose threshold oracles through revert order — Does allocate/internalTransfer revert order leak encrypted thresholds?

## Auditor claim

High severity. See [report §H-08](../report.md).

## Code references

`AccountFacetImpl.sol:52,59,61,140,146,148`

## Suggested test seam

test/AccountFacet.behavior.ts — vary amounts, compare revert reason/order

## Auditor recommendation

Reorder: public checks before encrypted predicate decrypt

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
