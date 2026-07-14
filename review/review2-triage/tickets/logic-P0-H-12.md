---
id: logic-P0-H-12
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-12
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-12: settleAndForceClosePosition settles against caller not quote PartyA — Does third-party caller cause settlement to check wrong PartyA?

## Auditor claim

High severity. See [report §H-12](../report.md).

## Code references

`SettleAndForceCloseFacet.sol:26; ForceActionsFacetImpl.sol:179,180; LibSettlement.sol:53`

## Suggested test seam

test/SettleAndForceClosePosition.behavior.ts — third party force-close with settlement

## Auditor recommendation

Pass quote.partyA into settlement or restrict to PartyA

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
