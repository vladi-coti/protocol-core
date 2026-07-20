---
id: privacy-P2-M-24
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: M-24
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-24: Emergency close emits close price as plaintext — Is emergency close price public in event while other closes encrypted?

## Auditor claim

Medium severity. See [report §M-24](../report.md).

## Code references

`IPartyBPositionActionsEvents.sol:12,17; RecoveryActionsFacet.sol:39,45`

## Suggested test seam

test/EmergencyClosePosition.behavior.ts — event inspection

## Auditor recommendation

Encrypt event or document emergency as public-price

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] If valid: write implement brief — N/A (accepted public)

## Answer

**Verdict:** `design-choice`  
**Disposition:** `wontfix`

`EmergencyClosePosition.closedPrice` is plaintext `uint256` and equals `upnlSig.price` from `PairUpnlAndPriceSig`. Under H-01 path C, Muon mark prices are intentionally public and already present in calldata — encrypting only the event hides nothing.

Do **not** “fix consistency” by plaintexting fill/force close events:
- **Fill close** — execution price arrives as `itUint256`; event encryption is load-bearing.
- **Force close** — emitted price is computed from private `requestedClosePrice` ± gap/penalty (muxed vs Muon average); plaintext would leak private close intent.

Emergency is the public-price path; document it as such. `filledAmount` stays `ctUint256`.

**Regression:** `test/audit/M24.test.ts` (locks intentional public `closedPrice`)

```bash
npx hardhat test --network localSimCoti test/audit/M24.test.ts --grep "M-24"
```
