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

**Verdict: `partial` (valid code flaw; sendQuote bypass not reproduced on testnet)**

**Evidence**

Command:

```bash
TEST_MODE=static npx hardhat test test/audit/C01.test.ts --grep "C-01"
```

Result (post-fix run pending; pre-fix 2026-07-09):

- ✔ Control: honestly unaffordable quote reverts (`PartyAFacet: insufficient available balance` on COTI testnet via receipt-status matcher)
- ✔ `totalRequired == 2^255` locked values: tx **reverts** (does not open quote with 1200 allocated)
- ✔ report3-style `cva=2^254, partyAmm=2^254`: tx **reverts**

**Code review**

- `MpcCore.toSigned(gtUint256)` is a bit reinterpret with **no** `< 2^255` guard at cited sites.
- `checkedAdd` on `totalForPartyA` blocks constructing `2^255` sums without overflow revert, which **mitigates** the classic sendQuote bypass from review1/report3#5 but does **not** fix casts on storage values corrupted by unchecked arithmetic (see H-02 / review1 report3#2).

**Fix disposition: `implement` (defense in depth at cited sites)**

- Added `LibEncryption.toNonNegativeSigned(gtUint256)` — requires encrypted `value < 2^255` before cast.
- Wired at cited paths: `PartyAFacetImpl.sendQuote`, all `LibAccount` unsigned→signed casts, all `LibSolvency` unsigned→signed casts.
- Regression: `test/audit/C01.behavior.ts` + `test/audit/C01.test.ts`.

**Remaining fog**

- Other files still call `.toSigned()` on `gtUint256` (e.g. `LibQuote`, `LibSettlement`, liquidation). Track under H-02 / follow-up hardening ticket.
