---
id: logic-P3-L-05
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-05
severity: Low
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-05: Next-ID views return current last ID not next ID — Do next-ID helpers return lastId instead of lastId+1?

## Auditor claim

Low severity. See [report §L-05](../report.md).

## Code references

`ViewFacet.sol:1141,1142; NextQuoteIDVerifier.sol:21,27`

## Suggested test seam

Compare helper output to actual next assigned ID

## Auditor recommendation

Return lastId+1 or rename helpers

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
