---
id: design-M-13-observer-rotation
labels: [group:design-product, wayfinder:grilling]
priority: P1
finding: M-13
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-13: Decide trusted observer rotation model — Is forward-only rotation acceptable or is migration required?

## Auditor claim

Medium severity. See [report §M-13](../report.md).

## Code references

`ControlFacet.sol:527,533; LibEncryption.sol:34,47; ViewFacet.sol:460,466`

## Suggested test seam

N/A — grilling session

## Auditor recommendation

Migration process or document forward-only

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
