---
id: privacy-P1-H-06
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-06
severity: High
status: closed
disposition: wontfix
blocks: —
blocked_by: design-H-13-free-collateral-privacy
report: ../report.md
---

## Question

H-06: Account allocation events leak private balance deltas — Do Allocate/Deallocate events emit plaintext amounts?

## Auditor claim

High severity. See [report §H-06](../report.md).

## Code references

`IAccountEvents.sol:12,13; AccountFacet.sol:55,93; MultiAccount.sol:264`

## Suggested test seam

test/EventAbi.behavior.ts or tx receipt log inspection

## Auditor recommendation

Encrypted events or accept public deltas (see design-H-13)

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1 — N/A (follows H-13)
- [x] Run test; record command + output — N/A
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A

## Answer

**Verdict: `design-choice`. Disposition: `wontfix`.**

Follows [H-13](design-H-13-free-collateral-privacy.md): free collateral is intentionally public. Encrypting Allocate/Deallocate event amounts while `balances` / ERC-20 transfers stay readable does not create a meaningful privacy boundary (free balance delta ≈ allocate/deallocate size). Revisit only if private tokens / private deposits land.
