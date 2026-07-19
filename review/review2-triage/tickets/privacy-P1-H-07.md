---
id: privacy-P1-H-07
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-07
severity: High
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-07: Reserve vault and fee collector events leak private amounts — Do reserve/fee events emit plaintext movement amounts?

## Auditor claim

High severity. See [report §H-07](../report.md).

## Code references

`IAccountEvents.sol:24,25; AccountManagementFacet.sol:18,25`

## Suggested test seam

Event inspection on reserve deposit/withdraw/claim

## Auditor recommendation

Encrypted event fields or classify as public

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1 — N/A (follows H-13 product boundary)
- [x] Run test; record command + output — N/A
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A

## Answer

**Verdict: `design-choice`. Disposition: `wontfix`.**

Confirmed leak shape: `DepositToReserveVault` / `WithdrawFromReserveVault` / `ClaimFeeCollectorBalance` emit plaintext `amount` while reserve/fee **storage** is encrypted.

Under [H-13](design-H-13-free-collateral-privacy.md), free collateral is intentionally public. Deposit/withdraw/claim all move against that public free ledger, so the movement size is already recoverable from free-balance deltas without reading the event. Encrypting only the event field is theater for the current (non–private-token) stack.

Revisit if private tokens / private free balances land later.
