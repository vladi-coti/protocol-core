---
id: privacy-P1-H-27
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-27
severity: High
status: closed
disposition: wontfix
blocks: —
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

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1 — N/A (follows H-13)
- [x] Run test; record command + output — N/A
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A

## Answer

**Verdict: `design-choice`. Disposition: `wontfix`.**

Follows [H-13](design-H-13-free-collateral-privacy.md): account movement amounts in calldata stay public with the free-collateral ledger. Encrypting only ABI inputs without private tokens / private deposits is out of scope. Revisit if that stack lands later.
