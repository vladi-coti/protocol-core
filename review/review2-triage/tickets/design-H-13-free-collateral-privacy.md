---
id: design-H-13-free-collateral-privacy
labels: [group:design-product, wayfinder:grilling]
priority: P0
finding: H-13
severity: High
status: closed
disposition: wontfix
blocks: privacy-P1-H-06, privacy-P1-H-27
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

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1 — N/A (product decision)
- [x] Run test; record command + output — N/A
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A (accepted as public)

## Answer

**Verdict: `design-choice`. Disposition: `wontfix`.**

Free collateral / bridge ledgers (`AccountStorage.balances`, `balanceOf`, deposit/withdraw amounts) remain **intentionally public** for the current product scope.

**Why:** real privacy for deposited amounts requires **private tokens with encrypted balances** (or equivalent deposit obfuscation). Plain ERC-20 `Transfer` to/from the diamond already publishes deposit/withdraw size; encrypting only the internal `balances` map without that is theater. Private tokens are **out of scope now** (maybe later).

**Privacy boundary (current):** protect trading-risk state (allocated / locked / positions / on-chain UPNL). Unallocated free collateral and bridge movements are public by design until a private-token / private-deposit path exists.

**Downstream:** H-06 / H-27 allocate/deallocate amounts are largely reconstructible from public free-balance deltas — accepted under the same decision (see those tickets).
