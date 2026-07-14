---
id: logic-P0-H-15
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-15
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-15: PartyB liquidation reverts when remaining LF exceeds allocated balance — Can insolvent PartyB with positive UPNL cause LF subtraction revert?

## Auditor claim

High severity. See [report §H-15](../report.md).

## Code references

`LibAccount.sol:225,232; LibLiquidation.sol:49,55,96,97`

## Suggested test seam

test/LiquidationFacet.behavior.ts — positive UPNL, LF > allocated

## Auditor recommendation

Cap remaining LF to payable allocated balance

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
