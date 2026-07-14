---
id: logic-P3-L-08
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-08
severity: Low
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-08: Fee distributor retains rounding dust, reports full claim — Does distributor event overstate distributed amount?

## Auditor claim

Low severity. See [report §L-08](../report.md).

## Code references

`SymmioFeeDistributor.sol:173,177,178,181`

## Suggested test seam

Fee claim with indivisible amount across stakeholders

## Auditor recommendation

Track dust or transfer remainder

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
