---
id: logic-P0-H-26
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-26
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-26: Force-close PartyB liquidation uses post-close balance without closing quote — Does liquidation use post-close availability while quote still open in storage?

## Auditor claim

High severity. See [report §H-26](../report.md).

## Code references

`ForceActionsFacetImpl.sol:160,178; LibSolvency.sol:183,186; LibLiquidation.sol:49,55`

## Suggested test seam

test/ForceClosePosition.behavior.ts — PartyB insolvent on simulated close

## Auditor recommendation

Close quote before liquidation or use consistent pre-close state

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
