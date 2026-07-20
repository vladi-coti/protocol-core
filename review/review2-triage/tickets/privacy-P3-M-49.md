---
id: privacy-P3-M-49
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-49
severity: Medium
status: closed
disposition: wontfix
blocks: —
blocked_by: design-M-49-quote-metadata-privacy
report: ../report.md
---

## Question

M-49: Public quote metadata leaks private trading intent — Are symbol/side/orderType/deadline/whitelist public while amounts encrypted?

## Auditor claim

Medium severity. See [report §M-49](../report.md).

## Code references

`QuoteStorage.sol`; `PartyAFacet.sol`; `ViewFacet` quote views

## Suggested test seam

Quote creation calldata + view inspection

## Auditor recommendation

See design-M-49 for privacy scope decision

## Resolution checklist

- [x] Read cited code paths in current branch
- [x] Design decision: [design-M-49](design-M-49-quote-metadata-privacy.md) — numbers-only
- [x] Verdict: `design-choice`
- [x] Fix disposition: `wontfix`
- [x] Regression documents intentional public metadata

## Answer

**Verdict:** `design-choice`  
**Disposition:** `wontfix`

Confirmed: numerics encrypted; intent/routing metadata public. Accepted under numbers-only privacy model.

No code change. Policy: [design-M-49](design-M-49-quote-metadata-privacy.md).

**Regression:** `test/audit/M49.test.ts`

```bash
npx hardhat test --network localSimCoti test/audit/M49.test.ts --grep "M-49"
```
