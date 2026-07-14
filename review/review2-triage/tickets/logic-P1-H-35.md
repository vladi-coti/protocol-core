---
id: logic-P1-H-35
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-35
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-35: Permissionless force close captures PartyB liquidation reward — Does arbitrary msg.sender receive liquidator share on force-close liquidation?

## Auditor claim

High severity. See [report §H-35](../report.md).

## Code references

`ForceCloseFacet.sol:23; ForceActionsFacetImpl.sol:177,183; LibLiquidation.sol:131`

## Suggested test seam

test/ForceClosePosition.behavior.ts — third party captures reward

## Auditor recommendation

Pay reward to authorized liquidator or protocol

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
