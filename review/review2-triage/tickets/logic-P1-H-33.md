---
id: logic-P1-H-33
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-33
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-33: Fee distributor cannot claim encrypted fee accruals — Are fees stuck in encrypted collector when distributor is fee collector?

## Auditor claim

High severity. See [report §H-33](../report.md).

## Code references

`LibPartyBPositionsActions.sol:50,70; SymmioFeeDistributor.sol:154,168`

## Suggested test seam

test/FeeDistributor.behavior.ts — accrue encrypted fees, claimAllFee

## Auditor recommendation

Add encrypted fee claim step to distributor

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
