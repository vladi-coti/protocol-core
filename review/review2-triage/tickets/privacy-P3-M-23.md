---
id: privacy-P3-M-23
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-23
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-23: Observer events missing for partial-fill child quotes — Does partial fill omit observer child quote event?

## Auditor claim

Medium severity. See [report §M-23](../report.md).

## Code references

`PartyBGroupActionsFacetImpl.sol:61,96`

## Suggested test seam

Partial fill flow — compare party events vs observer events

## Auditor recommendation

Emit observer child quote event on partial fill

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
