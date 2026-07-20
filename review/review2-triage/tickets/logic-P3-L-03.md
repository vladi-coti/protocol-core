---
id: logic-P3-L-03
labels: [group:logic-security, wayfinder:research]
priority: P3
finding: L-03
severity: Low
status: closed
disposition: wontfix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

L-03: editAccountName lacks account ownership validation — Can caller mutate wrong account while event references victim?

## Auditor claim

Low severity. See [report §L-03](../report.md).

## Code references

`MultiAccount.sol:231-234`

## Suggested test seam

MultiAccount.behavior.ts — editAccountName with foreign address

## Auditor recommendation

Require ownership of accountAddress

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

`editAccountName` only writes `accounts[msg.sender][index]` — the caller's own account list. A foreign `accountAddress` does not mutate the victim's storage, funds, or ownership. At most the caller renames the wrong one of **their** accounts (shared index) and the event can cite a misleading address.

No cross-account harm; not a privacy issue; no change.

**Regression:** `test/audit/L03.test.ts` (documents caller-only write semantics)

```bash
npx hardhat test --network localSimCoti test/audit/L03.test.ts --grep "L-03"
```
