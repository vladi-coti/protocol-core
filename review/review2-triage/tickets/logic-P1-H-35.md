---
id: logic-P1-H-35
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-35
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
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

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** `liquidatePartyBFromAvailable` credited LF tip to `msg.sender`. Direct `liquidatePartyB` is role-gated; force close is permissionless → third party can capture the tip.

**Fix:** pass explicit `liquidator` into `liquidatePartyBFromAvailable`; force-close path uses `quote.partyA`; role-gated path still uses `msg.sender`.

**Evidence:** dual PASS `test/audit/H35.test.ts`
