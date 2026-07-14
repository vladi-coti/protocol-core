---
id: logic-P2-M-02
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-02
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-02: Same-timestamp old liquidation prices can be reused — Can later liquidation reuse stale symbol prices with same timestamp?

## Auditor claim

Medium severity. See [report §M-02](../report.md).

## Code references

`AccountStorage.sol:43,45; LiquidationFacetImpl.sol:156,254,502,509`

## Suggested test seam

Liquidation test with repeated timestamp

## Auditor recommendation

Bind prices to liquidation id or clear on cleanup

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
