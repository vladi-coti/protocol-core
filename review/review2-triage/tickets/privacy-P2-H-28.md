---
id: privacy-P2-H-28
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: H-28
severity: High
status: closed
disposition: implement
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

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict:** `valid`  
**Disposition:** `implement` (done)

Public quote/position views returned storage `Quote` / `utUint256` (system `ciphertext` + `userCiphertext`). Account balance views already return `ctUint256` only.

### Fix

Not zeroing husks on `Quote`. New public type `ViewQuote` (and `UserLockedValues` for locks) with **only** `ctUint256` fields. All quote/position view APIs return `ViewQuote` / `ViewQuote[]` via `_toViewQuote` / `_toObserverViewQuote`. Storage `Quote` unchanged.

### Evidence

```bash
npx hardhat test --network localSimCoti test/audit/H28.test.ts --grep "H-28"
# 2 passing — dual PASS vs testnet
```

### Implement brief

- `QuoteStorage.ViewQuote` — metadata + flat user/observer ciphertext
- `IViewFacet` / `ViewFacet` quote getters return `ViewQuote`
- Regression: `test/audit/H28.test.ts` (ABI + live flat-ct shape)
- **ABI break** for clients decoding `getQuote` as `utUint256`
