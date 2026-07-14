---
id: logic-P2-M-26
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-26
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-26: uint8 loop counters make large batches revert — Do batch loops revert when array length > 255?

## Auditor claim

Medium severity. See [report §M-26](../report.md).

## Code references

`MultiAccount.sol:295; PartyAFacet.sol:143; LibSettlement.sol:50`

## Suggested test seam

Batch test with 256+ entries

## Auditor recommendation

Use uint256 counters or explicit size caps

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
