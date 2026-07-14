---
id: privacy-P3-M-40
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-40
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-40: Trusted observer events missing for position execution — Do open/close execution paths skip observer execution events?

## Auditor claim

Medium severity. See [report §M-40](../report.md).

## Code references

`IPartiesEvents.sol:39,46; PartyBPositionActionsFacet.sol:39,43`

## Suggested test seam

Open/close fill — compare user vs observer events

## Auditor recommendation

Emit observer execution events

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
