---
id: design-M-49-quote-metadata-privacy
labels: [group:design-product, wayfinder:grilling]
priority: P2
finding: M-49
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-49: Decide quote metadata privacy scope — Which quote metadata must be private vs acceptable public?

## Auditor claim

Medium severity. See [report §M-49](../report.md).

## Code references

`PartyAFacet.sol:22,64; QuoteStorage.sol:69`

## Suggested test seam

N/A — grilling session

## Auditor recommendation

Document public metadata; encrypt/commit rest if needed

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
