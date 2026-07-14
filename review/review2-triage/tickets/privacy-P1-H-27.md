---
id: privacy-P1-H-27
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-27
severity: High
status: open
blocks: design-H-13-free-collateral-privacy
blocked_by: design-H-13-free-collateral-privacy
report: ../report.md
---

## Question

H-27: Account balance deltas remain public calldata — Are movement amounts public uint256 in account APIs?

## Auditor claim

High severity. See [report §H-27](../report.md).

## Code references

`AccountFacet.sol:49,87; AccountFacetImpl.sol:53,77`

## Suggested test seam

Calldata inspection on allocate/deallocate/transfer

## Auditor recommendation

Encrypted COTI inputs or accept public (see design-H-13)

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
