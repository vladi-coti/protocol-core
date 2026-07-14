---
id: logic-P1-H-34
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-34
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-34: Expired close requests can still be force closed — Can force close execute after deadline if price window predates deadline?

## Auditor claim

High severity. See [report §H-34](../report.md).

## Code references

`PartyAFacetImpl.sol:224,249,256; ForceActionsFacetImpl.sol:82,84`

## Suggested test seam

test/ForceClosePosition.behavior.ts — force close after deadline

## Auditor recommendation

Require block.timestamp <= quote.deadline

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
