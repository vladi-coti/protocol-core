---
id: logic-P2-M-15
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-15
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-15: priceValidTime configured but not enforced — Is priceValidTime ignored on price-bearing Muon paths?

## Auditor claim

Medium severity. See [report §M-15](../report.md).

## Code references

`MuonStorage.sol:139,140; LibMuonPartyA.sol:15; LibMuonPartyB.sol:13`

## Suggested test seam

Muon signature test with stale price outside priceValidTime

## Auditor recommendation

Enforce priceValidTime everywhere or remove setting

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
