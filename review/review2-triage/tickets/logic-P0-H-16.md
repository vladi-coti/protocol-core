---
id: logic-P0-H-16
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-16
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-16: Deferred liquidation type uses current balance not signed snapshot — Can balance change between snapshot and execution alter liquidation type? (Check review1#4 fix status)

## Auditor claim

High severity. See [report §H-16](../report.md).

## Code references

`MuonStorage.sol:67,72; DeferredLiquidationFacetImpl.sol:39,41,49,52`

## Suggested test seam

Deferred liquidation test with balance mutation between sign and execute

## Auditor recommendation

Use signed snapshot for type and accounting consistently

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
