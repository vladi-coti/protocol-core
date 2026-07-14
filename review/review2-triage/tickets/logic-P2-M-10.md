---
id: logic-P2-M-10
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-10
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-10: Suspension does not block several user state-changing paths — Can suspended PartyA deallocate, cancel, or request close?

## Auditor claim

Medium severity. See [report §M-10](../report.md).

## Code references

`ControlFacet.sol:473,478; AccountFacet.sol:87; PartyAFacet.sol:161,182,242`

## Suggested test seam

ControlFacet.behavior.ts — suspended PartyA paths

## Auditor recommendation

Apply suspension consistently or document exceptions

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
