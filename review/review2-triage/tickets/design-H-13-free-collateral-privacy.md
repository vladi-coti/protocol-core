---
id: design-H-13-free-collateral-privacy
labels: [group:design-product, wayfinder:grilling]
priority: P0
finding: H-13
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-13: Decide free collateral and bridge amount privacy model — Should free collateral/bridge remain public or be encrypted? Product decision gates H-06, H-27 fixes.

## Auditor claim

High severity. See [report §H-13](../report.md).

## Code references

`AccountStorage.sol:52,53; AccountFacetImpl.sol:26,30; ViewFacet.sol:30,31`

## Suggested test seam

N/A — grilling session with maintainer

## Auditor recommendation

Encrypt ledger OR document as intentionally public

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
