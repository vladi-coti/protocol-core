---
id: logic-P3-L-06
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-06
severity: Low
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-06: PartyB-filtered position views scan wrong range — Do PartyB position views return sparse default structs?

## Auditor claim

Low severity. See [report §L-06](../report.md).

## Code references

`ViewFacet.sol:666,701,746`

## Suggested test seam

PartyB position view with non-dense quote IDs

## Auditor recommendation

Page actual quote IDs, return compact arrays

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
