---
id: logic-P2-M-50
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-50
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-50: Dust close requests lock positions until cancel/deadline — Can dust close request enter CLOSE_PENDING but fail execution?

## Auditor claim

Medium severity. See [report §M-50](../report.md).

## Code references

`PartyAFacetImpl.sol:229,237; ForceActionsFacetImpl.sol:147,182; LibQuote.sol:189`

## Suggested test seam

Close request with quantity causing zero proportional LF release

## Auditor recommendation

Validate minimum proportional close at request time

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
