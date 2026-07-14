---
id: logic-P0-H-14
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-14
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-14: Force-close liquidation ignores reserve credit when computing PartyB deficit — Does PartyB liquidation use pre-reserve available balance after reserve credit applied?

## Auditor claim

High severity. See [report §H-14](../report.md).

## Code references

`ForceActionsFacetImpl.sol:160,185,208,213,219; LibLiquidation.sol:49,55`

## Suggested test seam

test/ForceClosePosition.behavior.ts — insolvent PartyB with partial reserve

## Auditor recommendation

Recompute available balance after reserve credit

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
