---
id: logic-P3-L-01
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-01
severity: Low
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-01: Liquidation-fee splits silently discard rounding remainders — Is rounding dust lost on liquidation fee split?

## Auditor claim

Low severity. See [report §L-01](../report.md).

## Code references

`LiquidationFacetImpl.sol:481,485; LibLiquidation.sol:55,57`

## Suggested test seam

Liquidation with indivisible fee amount

## Auditor recommendation

Assign remainders deterministically

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
