---
id: logic-P2-M-10
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-10
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-10: Suspension does not block several user state-changing paths — Can suspended PartyA deallocate, cancel, or request close?

## Auditor claim

Medium severity. See [report §M-10](../report.md).

## Code references

`ControlFacet.sol:473,478; AccountFacet.sol:87; PartyAFacet.sol:161,182,242`

## Suggested test seam

ControlFacet.behavior.ts — suspended PartyA paths

## Auditor recommendation

Apply suspension consistently or document exceptions

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement` (done)
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

`notSuspended` gated `sendQuote` / allocate / withdraw but **not** `deallocate`, `deallocateWithQuotePrices`, `requestToCancelQuote`, `requestToClosePosition`, or `requestToCancelCloseRequest`. Suspended PartyA could still move allocation and mutate quote lifecycle.

**Fix:** add `notSuspended(msg.sender)` on those five entrypoints.

**Regression:** `test/audit/M10.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M10.test.ts --grep 'M-10'
# sim: 2/2 PASS
```
