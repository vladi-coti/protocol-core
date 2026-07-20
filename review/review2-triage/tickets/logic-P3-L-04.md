---
id: logic-P3-L-04
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-04
severity: Low
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-04: Pagination views underflow when start exceeds length — Do pagination views revert when start >= length?

## Auditor claim

Low severity. See [report §L-04](../report.md).

## Code references

`ViewFacet.sol:400,404; MultiAccount.sol:327,328`

## Suggested test seam

View call with start > length

## Auditor recommendation

Return empty array when start >= length

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A

## Answer

**Verdict:** `design-choice`  
**Disposition:** `wontfix`

Confirmed: `start > length` / `lastId` hits `length - start` under Solidity 0.8 → panic `0x11`. Soft-empty pages are a common API convention, not a protocol requirement.

Invalid pagination range should fail loud (caller off-by-one stays visible). No funds / privacy impact. ViewFacet + MultiAccount left unchanged.

**Regression:** `test/audit/L04.test.ts` (documents intentional revert)

```bash
npx hardhat test --network localSimCoti test/audit/L04.test.ts --grep "L-04"
```
