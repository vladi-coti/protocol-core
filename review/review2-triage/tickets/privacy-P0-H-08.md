---
id: privacy-P0-H-08
labels: [group:privacy-leak, wayfinder:research]
priority: P0
finding: H-08
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-08: Account balance checks expose threshold oracles through revert order — Does allocate/internalTransfer revert order leak encrypted thresholds?

## Auditor claim

High severity. See [report §H-08](../report.md).

## Code references

`AccountFacetImpl.sol:52,59,61,140,146,148`

## Suggested test seam

test/AccountFacet.behavior.ts — vary amounts, compare revert reason/order

## Auditor recommendation

Reorder: public checks before encrypted predicate decrypt

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** `allocate` / `internalTransfer` decrypted the allocated-balance limit before checking plaintext free balance. Underfunded caller + amount that would also breach limit reverted with `"Allocated balance limit reached"` first → private threshold oracle.

**Evidence (sim)**

```bash
TEST_MODE=static npx hardhat test test/audit/H08.test.ts --grep 'H-08' --network localSimCoti
```

- Red: free=50, limit=100, allocate/internalTransfer(200) → limit-reached first.
- Green: same → `"Insufficient balance"`; source-order check public require before limit string.

- Dual: `localSimCoti` + `coti-testnet` PASS (`sim-vs-testnet.md`).

**Fix:** public `balances[msg.sender] >= amount` before encrypted limit decrypt in both functions.

**Regression:** `test/audit/H08.test.ts` / `H08.behavior.ts`
