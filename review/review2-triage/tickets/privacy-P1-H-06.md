---
id: privacy-P1-H-06
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-06
severity: High
status: open
blocks: design-H-13-free-collateral-privacy
blocked_by: design-H-13-free-collateral-privacy
report: ../report.md
---

## Question

H-06: Account allocation events leak private balance deltas — Do Allocate/Deallocate events emit plaintext amounts?

## Auditor claim

High severity. See [report §H-06](../report.md).

## Code references

`IAccountEvents.sol:12,13; AccountFacet.sol:55,93; MultiAccount.sol:264`

## Suggested test seam

test/EventAbi.behavior.ts or tx receipt log inspection

## Auditor recommendation

Encrypted events or accept public deltas (see design-H-13)

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
