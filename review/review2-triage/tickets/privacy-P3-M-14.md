---
id: privacy-P3-M-14
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-14
severity: Medium
status: open
blocks: design-M-13-observer-rotation
blocked_by: design-M-13-observer-rotation
report: ../report.md
---

## Question

M-14: Observer balance-change events missing for non-accounting mutations — Do fee/PnL/liquidation balance mutations skip observer events?

## Auditor claim

Medium severity. See [report §M-14](../report.md).

## Code references

`SharedEvents.sol:29,31; LibQuote.sol:253,263`

## Suggested test seam

Compare storage mutations vs observer event emission

## Auditor recommendation

Emit observer events for all encrypted balance mutations

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
