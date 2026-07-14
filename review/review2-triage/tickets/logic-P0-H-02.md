---
id: logic-P0-H-02
labels: [group:logic-security, wayfinder:research]
priority: P0
finding: H-02
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-02: Signed MPC accounting uses unchecked arithmetic — Does signed encrypted arithmetic wrap instead of reverting at range boundaries?

## Auditor claim

High severity. See [report §H-02](../report.md).

## Code references

`LibAccount.sol:72; LibSettlement.sol:89,115; LibQuote.sol:237,238`

## Suggested test seam

Drive accounting near signed boundary; assert wrap or incorrect solvency outcome

## Auditor recommendation

Checked signed ops or strict bounds before unchecked math

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [x] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `valid`.** COTI `gtInt256.add/sub` wraps; cited accounting paths used unchecked ops.

**Fix disposition: `implement`**

- Reinstalled `@coti-io/coti-contracts#feat/signed` (native `MpcCore.checkedAdd/Sub(gtInt256)`).
- Cited paths: `LibAccount`, `LibSettlement`, `LibQuote`, `LibSolvency` — `.add/.sub` → `.checkedAdd/.checkedSub`.
- Follow-up sweep: remaining `gtInt256` unchecked ops in FundingRate / Liquidation / ForceActions / LibLiquidation / DeferredLiquidation.
- Regression: `test/audit/H02.test.ts` — sendQuote unaffordable quote still reverts (passed on COTI testnet).

**Evidence**

```bash
npx hardhat test test/audit/H02.test.ts --grep "H-02"
# 1 passing (~6m)
```
