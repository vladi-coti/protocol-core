---
id: logic-P3-L-08
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-08
severity: Low
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-08: Fee distributor retains rounding dust, reports full claim — Does distributor event overstate distributed amount?

## Auditor claim

Low severity. See [report §L-08](../report.md).

## Code references

`SymmioFeeDistributor.sol` claimFee / dryClaimAllFee

## Suggested test seam

Fee claim with indivisible amount across stakeholders

## Auditor recommendation

Track dust or transfer remainder

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief — see Answer

## Answer

**Verdict:** `valid`  
**Disposition:** `implement`

`claimFee` floored each `(share * amount) / 1e18` independently. With shares summing to 100%, dust stayed in the distributor while `FeesClaimed(amount)` reported the full withdraw.

**Fix:** last stakeholder receives `amount - distributed` remainder (same in `dryClaimAllFee`). Full amount leaves the contract; event matches transfers.

**Regression:** `test/audit/L08.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/L08.test.ts --grep "L-08"
```

Sim: 2 passing (previously distributed 100 vs claimed 101).
