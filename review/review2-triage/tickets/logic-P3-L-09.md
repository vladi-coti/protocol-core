---
id: logic-P3-L-09
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-09
severity: Low
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-09: Multicall result arrays empty for successful calls — Does multicall discard successful subcall return data?

## Auditor claim

Low severity. See [report §L-09](../report.md).

## Code references

`contracts/dev/multicall.sol:88,93,95,131,136,138`

## Suggested test seam

Multicall aggregate test asserting return bytes

## Auditor recommendation

Write to returnData[i] directly

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `invalid`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A

## Answer

**Verdict:** `invalid`  
**Disposition:** `wontfix`

**One-liner:** memory struct assign aliases; field writes already update `returnData[i]`.

Auditor misread Solidity memory semantics. In `tryAggregate` / `aggregate3` / `aggregate3Value`:

```solidity
Result memory result = returnData[i];
(result.success, result.returnData) = call.target.call(...);
```

Memory→memory struct assignment is a **reference**, not a deep copy. Field writes on `result` update `returnData[i]`. Runtime proves non-empty decoded return data for successful subcalls.

No contract change. Optional cosmetic `returnData[i] = result` would only reduce reader confusion.

**Regression:** `test/audit/L09.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/L09.test.ts --grep "L-09"
```
