---
id: privacy-P2-H-28
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: H-28
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-28: Quote views expose COTI system ciphertexts — Do public views return full utUint256 structs with system ciphertext?

## Auditor claim

High severity. See [report §H-28](../report.md).

## Code references

`QuoteStorage.sol:69,76; ViewFacet.sol:456,457,531`

## Suggested test seam

ViewFacet quote/position calls — inspect returned ciphertext fields

## Auditor recommendation

Redacted view types per caller role

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
