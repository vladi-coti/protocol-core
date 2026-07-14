---
id: logic-P1-H-32
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-32
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-32: Emergency close blocked when party already insolvent — Does emergency close revert when either party is insolvent?

## Auditor claim

High severity. See [report §H-32](../report.md).

## Code references

`RecoveryActionsFacet.sol:28,31; PartyBPositionActionsFacetImpl.sol:84,105`

## Suggested test seam

test/EmergencyClosePosition.behavior.ts — insolvent party in emergency mode

## Auditor recommendation

Emergency settlement path through reserve/liquidation

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
