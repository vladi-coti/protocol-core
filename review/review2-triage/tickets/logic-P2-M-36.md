---
id: logic-P2-M-36
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-36
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-36: Deferred liquidation reimbursement underflow — Does positive UPNL make reimbursement subtraction underflow?

## Auditor claim

Medium severity. See [report §M-36](../report.md).

## Code references

`DeferredLiquidationFacetImpl.sol:49,53; LibAccount.sol:122,124`

## Suggested test seam

Deferred liquidation with availability > allocated

## Auditor recommendation

Cap reimbursement to allocated collateral

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
