---
id: privacy-P1-H-07
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-07
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-07: Reserve vault and fee collector events leak private amounts — Do reserve/fee events emit plaintext movement amounts?

## Auditor claim

High severity. See [report §H-07](../report.md).

## Code references

`IAccountEvents.sol:24,25; AccountManagementFacet.sol:18,25`

## Suggested test seam

Event inspection on reserve deposit/withdraw/claim

## Auditor recommendation

Encrypted event fields or classify as public

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
