---
id: logic-P2-M-11
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-11
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-11: Global pause does not stop internal transfers — Does internalTransfer work under pauseGlobal alone?

## Auditor claim

Medium severity. See [report §M-11](../report.md).

## Code references

`Pausable.sol:10,12; ControlFacet.sol:389,391; AccountFacet.sol:107,110`

## Suggested test seam

test/AccountFacet.behavior.ts — global pause + internalTransfer

## Auditor recommendation

Include globalPaused in internal-transfer modifier

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement` (done)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

`whenNotInternalTransferPaused` checked `internalTransferPaused` + `accountingPaused` but **not** `globalPaused`, unlike every other pause modifier. `pauseGlobal()` alone left `internalTransfer` open.

**Fix:** require `!globalPaused` in `whenNotInternalTransferPaused` (`contracts/utils/Pausable.sol`).

**Regression:** `test/audit/M11.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M11.test.ts --grep 'M-11'
# sim: 2/2 PASS
```
