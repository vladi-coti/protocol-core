---
id: design-M-22-coti-dependencies
labels: [group:design-product, wayfinder:research]
priority: P1
finding: M-22
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-22: Decide COTI dependency pinning policy — Are COTI deps pinned to immutable commits?

## Auditor claim

Medium severity. See [report §M-22](../report.md).

## Code references

`package.json:10,11; .gitignore:2`

## Suggested test seam

Compare package.json refs vs lockfile presence

## Auditor recommendation

Pin to commits; track lockfile in repo

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
