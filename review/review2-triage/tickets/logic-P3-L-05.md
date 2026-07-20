---
id: logic-P3-L-05
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-05
severity: Low
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-05: Next-ID views return current last ID not next ID — Do next-ID helpers return lastId instead of lastId+1?

## Auditor claim

Low severity. See [report §L-05](../report.md).

## Code references

`ViewFacet.sol` getNextQuoteId / getNextBridgeTransactionId; `NextQuoteIDVerifier.sol`

## Suggested test seam

Compare helper output to actual next assigned ID

## Auditor recommendation

Return lastId+1 or rename helpers

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A

## Answer

**Verdict:** `design-choice`  
**Disposition:** `wontfix` (NatSpec only)

Confirmed: `getNextQuoteId()` / `getNextBridgeTransactionId()` return storage `lastId` (last assigned). Creation does `++lastId`, so the upcoming ID is `helper + 1`.

Changing the return to `lastId + 1` would break in-repo callers that already add one (`BridgeFacet.behavior.ts`: `id + 1n`) and `NextQuoteIDVerifier` (`require(quoteId == getNextQuoteId())` as last-assigned check). Renaming is an ABI break.

Keep behavior; clarify NatSpec that these return last assigned ID.

**Regression:** `test/audit/L05.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/L05.test.ts --grep "L-05"
```
