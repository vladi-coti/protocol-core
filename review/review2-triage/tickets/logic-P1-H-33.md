---
id: logic-P1-H-33
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-33
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-33: Fee distributor cannot claim encrypted fee accruals — Are fees stuck in encrypted collector when distributor is fee collector?

## Auditor claim

High severity. See [report §H-33](../report.md).

## Code references

`LibPartyBPositionsActions.sol:50,70; SymmioFeeDistributor.sol:154,168`

## Suggested test seam

test/FeeDistributor.behavior.ts — accrue encrypted fees, claimAllFee

## Auditor recommendation

Add encrypted fee claim step to distributor

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** Fees accrue to `encryptedFeeCollectorBalances`; `SymmioFeeDistributor.claimAllFee` only `balanceOf` + `withdraw`, so a distributor configured as fee collector underclaims (plaintext 0) while encrypted fees remain.

**Fix (landed):**
- `claimAllFeeCollectorBalance()` on AccountManagementFacet / AccountFacetImpl
- Distributor `claimAllFee` calls it before `getClaimable`/`withdraw`
- `setSymmioEncryptionAddress` on distributor (contract collectors need an onboarded EOA for offBoard)
- Empty-init paths in `LibAccount` no longer `offBoardToUser` to the account address (unblocks contract `setEncryptionAddress` bootstrap)

**Evidence:** dual PASS `test/audit/H33.test.ts`

```bash
./review/review2-triage/scripts/run-dual-network-test.sh 'H-33' test/audit/H33.test.ts 'H-33 fee distributor encrypted claim'
```
