---
id: logic-P2-M-11
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-11
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-11: Global pause does not stop internal transfers — Does internalTransfer work under pauseGlobal alone?

## Auditor claim

Medium severity. See [report §M-11](../report.md).

## Code references

`Pausable.sol:10,12; ControlFacet.sol:389,391; AccountFacet.sol:107,110`

## Suggested test seam

test/AccountFacet.behavior.ts — global pause + internalTransfer

## Auditor recommendation

Include globalPaused in internal-transfer modifier

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
