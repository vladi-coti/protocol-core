---
id: logic-P2-M-03
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-03
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-03: Liquidation dispute accumulator ignores CVA released at settlement — Does dispute check false-positive when CVA release omitted?

## Auditor claim

Medium severity. See [report §M-03](../report.md).

## Code references

`LiquidationFacetImpl.sol:88,90,95,99,414,416`

## Suggested test seam

Liquidation dispute scenario with CVA release

## Auditor recommendation

Include CVA in accumulator formula

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
