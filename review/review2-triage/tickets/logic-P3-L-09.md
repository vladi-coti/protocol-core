---
id: logic-P3-L-09
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-09
severity: Low
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-09: Multicall result arrays empty for successful calls — Does multicall discard successful subcall return data?

## Auditor claim

Low severity. See [report §L-09](../report.md).

## Code references

`contracts/dev/multicall.sol:88,93,95,131,136,138`

## Suggested test seam

Multicall aggregate test asserting return bytes

## Auditor recommendation

Write to returnData[i] directly

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
