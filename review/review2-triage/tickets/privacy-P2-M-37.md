---
id: privacy-P2-M-37
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: M-37
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-37: Liquidation dispute resolution accepts plaintext settlement amounts — Are dispute settlement amounts public int256[] calldata?

## Auditor claim

Medium severity. See [report §M-37](../report.md).

## Code references

`LiquidationResolutionFacet.sol:30,33; LiquidationFacetImpl.sol:367,370`

## Suggested test seam

Dispute resolution calldata inspection

## Auditor recommendation

Encrypted inputs or document as public

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

`resolveLiquidationDispute` took `int256[] amounts`, then `setPublic256` + `offBoardToUser`. Settlement actuals are trading-risk state (H-13 privacy boundary); encrypting after publishing calldata is theater.

### Fix

- ABI: `itInt256[] calldata amounts`
- Facet: `validateCiphertext` → `gtInt256[]` into impl (no `setPublic256`)
- Event still offBoards PartyA user ciphertext from the validated garbled values

### Evidence

```bash
npx hardhat test --network localSimCoti test/audit/M37.test.ts --grep "M-37"
# 2 passing — dual PASS vs testnet
```

### Implement brief

- `ILiquidationResolutionFacet` / `LiquidationResolutionFacet` / `LiquidationFacetImpl.resolveLiquidationDispute`
- Regression: `test/audit/M37.test.ts`
- **ABI break** for dispute callers (must encrypt amounts)
