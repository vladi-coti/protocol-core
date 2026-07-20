---
id: logic-P2-M-50
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-50
severity: Medium
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-50: Dust close requests lock positions until cancel/deadline — Can dust close request enter CLOSE_PENDING but fail execution?

## Auditor claim

Medium severity. See [report §M-50](../report.md).

## Code references

`PartyAFacetImpl.sol:229,237; ForceActionsFacetImpl.sol:147,182; LibQuote.sol:189`

## Suggested test seam

Close request with quantity causing zero proportional LF release

## Auditor recommendation

Validate minimum proportional close at request time

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

### Evidence

Red (pre-fix): `quantityToClose = 1` wei → `CLOSE_PENDING`; `fillCloseRequest` → `LibQuote: Low filled amount`.

Green (post-fix): same dust reverts at `requestToClosePosition`; full close still → `CLOSE_PENDING`.

```bash
npx hardhat test --network localSimCoti test/audit/M50.test.ts --grep "M-50"
# 3 passing
```

### Implement brief

- Extract `LibQuote.requireMinProportionalCloseAmount` (same CVA/MM/LF proportion rules as `closeQuote`).
- Call from `PartyAFacetImpl.requestToClosePosition` before state → `CLOSE_PENDING`.
- Regression: `test/audit/M50.test.ts`
