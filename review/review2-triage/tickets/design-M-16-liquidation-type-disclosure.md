---
id: design-M-16-liquidation-type-disclosure
labels: [group:design-product, wayfinder:grilling]
priority: P2
finding: M-16
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-16: Decide liquidation type disclosure policy — Is public LiquidationType intentional lifecycle disclosure?

## Auditor claim

Medium severity. See [report §M-16](../report.md).

## Code references

`LiquidationFacetImpl.sol` set-prices type assignment; `AccountStorage.LiquidationDetail`

## Suggested test seam

N/A — grilling session

## Auditor recommendation

Accept public type or redesign classification

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Grill / decide policy
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] Unblock privacy-P3-M-16

## Answer

**Decision:** keep **public**.

`LiquidationType` (NORMAL / LATE / OVERDUE) is intentional lifecycle disclosure. Exact deficit magnitude stays encrypted; severity bucket is public protocol state used by settlement branching and readable via `getLiquidatedStateOfPartyA`.

Hiding the bucket would require encrypted control flow or collapsing liquidation economics — out of scope for this privacy posture (same class as H-01 path C / H-13 public lifecycle fields).

**Gates:** [privacy-P3-M-16](privacy-P3-M-16.md) closed as design-choice / wontfix.
