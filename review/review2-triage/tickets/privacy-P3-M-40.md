---
id: privacy-P3-M-40
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-40
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-40: Trusted observer events missing for position execution — Do open/close execution paths skip observer execution events?

## Auditor claim

Medium severity. See [report §M-40](../report.md).

## Code references

`IPartiesEvents.sol:39,46; PartyBPositionActionsFacet.sol:39,43`

## Suggested test seam

Open/close fill — compare user vs observer events

## Auditor recommendation

Emit observer execution events

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `wontfix` (design-choice — poll views)
- [x] If valid: write implement brief — N/A

## Answer

**Verdict:** `valid`  
**Disposition:** `wontfix` (align M-14 / M-13 polling)

**One-liner:** no ObserverOpen/FillClose events; `LibEncryption` still updates `observerQuoteValues` — poll views.

Confirmed:
- ABI has `OpenPositionForPartyA/B` + `FillCloseRequestForPartyA/B` only — no observer execution events.
- Open/close write observer ciphertext via `storeQuoteOpenedPrice` / `storeQuoteClosedAmount` / etc.
- Runtime: party fill events present; zero `ObserverFill*`; observer `closedAmount` matches fill.

Same product choice as M-14: event-sourced observers incomplete; view/polling is source of truth. `ObserverSendQuote` (M-23) covers quote-create parity only.

**Regression:** `test/audit/M40.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M40.test.ts --grep "M-40"
```
