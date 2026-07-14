---
id: logic-P3-L-04
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-04
severity: Low
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-04: Pagination views underflow when start exceeds length — Do pagination views revert when start >= length?

## Auditor claim

Low severity. See [report §L-04](../report.md).

## Code references

`ViewFacet.sol:400,404; MultiAccount.sol:327,328`

## Suggested test seam

View call with start > length

## Auditor recommendation

Return empty array when start >= length

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
