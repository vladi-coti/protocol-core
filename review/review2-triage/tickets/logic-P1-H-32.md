---
id: logic-P1-H-32
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-32
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: design-choice
disposition: wontfix
---

## Question

H-32: Emergency close blocked when party already insolvent — Does emergency close revert when either party is insolvent?

## Auditor claim

High severity. See [report §H-32](../report.md).

## Code references

`RecoveryActionsFacet.sol:28,31; PartyBPositionActionsFacetImpl.sol:84,105`

## Suggested test seam

test/EmergencyClosePosition.behavior.ts — insolvent party in emergency mode

## Auditor recommendation

Emergency settlement path through reserve/liquidation

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict: `design-choice`. Disposition: `wontfix`.**

Auditor’s *behavior* claim is true: `emergencyClosePosition` requires both sides solvent (`PBF:A insol` / `PBF:B insol` at `PartyBPositionActionsFacetImpl.sol:105-106`) and `LibQuote.closeQuote` also rejects negative post-PnL balances. Existing suite already encodes this (`EmergencyClosePosition.behavior.ts` “Should fail on negative balance”).

Calling that High / “stuck positions” is trash. Emergency close is an orderly **solvent** unwind under global emergency / PartyB emergency / invalid symbol. Insolvency is the **liquidation** path; `LiquidationFacet` is not gated by `emergencyMode` or `partyBEmergencyStatus`. Confirmed: under PartyB emergency, insolvent UPNL still liquidates PartyB successfully while emergency close reverts.

A real insolvent emergency settlement (deficit → reserve/liquidation inside emergency close) is a **new product path**, not a one-line delete of two requires. Do not implement without an explicit design for deficit routing.

**Evidence (dual PASS)**

```bash
python3 utils/update_sig_checks.py 1
./review/review2-triage/scripts/run-dual-network-test.sh 'H-32' test/audit/H32.test.ts 'H-32 emergency close insolvency vs liquidation'
```

**Regression / lock-in:** `test/audit/H32.test.ts` / `H32.behavior.ts`
