---
id: logic-P0-C-01
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: C-01
severity: Critical
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

C-01: Unsigned encrypted values can become negative in signed solvency math — Is C-01 valid? Can oversized encrypted unsigned values cross into negative signed accounting?

## Auditor claim

Critical severity. See [report §C-01](../report.md).

## Code references

`PartyAFacetImpl.sol:92,96; LibAccount.sol:62,68; LibSolvency.sol:129,132`

## Suggested test seam

test/AccountFacet.behavior.ts or solvency path; encrypted boundary value near 2^255

## Auditor recommendation

Enforce signed-range bounds before every unsigned-to-signed encrypted conversion

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [x] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid` (hardened).** SendQuote high-bit bypass not reproduced; unsigned→signed casts guarded repo-wide.

**Evidence**

```bash
TEST_MODE=static npx hardhat test test/audit/C01.test.ts --network localSimCoti
# 4 passing (control + high-bit + report3-style + static no-raw-.toSigned tripwire)
```

**Fix disposition: `implement` (done)**

- `LibEncryption.toNonNegativeSigned(gtUint256)` — requires encrypted `value < 2^255` before cast.
- Cited paths: `PartyAFacetImpl.sendQuote`, all `LibAccount` / `LibSolvency` unsigned→signed casts.
- Follow-up sweep: remaining raw `.toSigned()` removed from `LibQuote`, `LibSettlement`, `FundingRateFacetImpl`, `ForceActionsFacetImpl`, `LiquidationFacetImpl` (PnL / impact / reserve / allocated magnitudes). Dispute amounts use direct `MpcCore.setPublic256(int256)`.
- Regression: `test/audit/C01.test.ts` — behavioral cases + contracts must not use raw `.toSigned()`.
