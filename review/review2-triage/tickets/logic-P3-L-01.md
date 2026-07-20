---
id: logic-P3-L-01
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-01
severity: Low
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-01: Liquidation-fee splits silently discard rounding remainders — Is rounding dust lost on liquidation fee split?

## Auditor claim

Low severity. See [report §L-01](../report.md).

## Code references

`LiquidationFacetImpl.sol:481,485; LibLiquidation.sol:55,57`

## Suggested test seam

Liquidation with indivisible fee amount

## Auditor recommendation

Assign remainders deterministically

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

Red: static failed — both liquidators got `lf/2`; PartyB had no remainder recirculation.

Green:

```bash
npx hardhat test --network localSimCoti test/audit/L01.test.ts --grep "L-01"
# 2 passing — dual PASS vs testnet
```

### Implement brief

- PartyA NORMAL: `gtLf2 = gtLf.checkedSub(gtLf1)` (not second `div(2)`).
- PartyB: after `perPosition = floor((remaining−liqShare)/n)`, add `(remaining−liqShare − perPosition*n)` back onto liquidator share.
- Regression: `test/audit/L01.test.ts`
