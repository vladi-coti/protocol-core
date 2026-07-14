---
id: privacy-P3-M-34
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-34
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-34: Balance-change event types leak PnL direction — Does REALIZED_PNL_IN vs OUT branch leak direction?

## Auditor claim

Medium severity. See [report §M-34](../report.md).

## Code references

`LibQuote.sol:262; LibSettlement.sol:124; LiquidationFacetImpl.sol:422`

## Suggested test seam

Settlement/liquidation event type inspection

## Auditor recommendation

Constant event shape like normal close path

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
