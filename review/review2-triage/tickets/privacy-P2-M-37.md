---
id: privacy-P2-M-37
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: M-37
severity: Medium
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-37: Liquidation dispute resolution accepts plaintext settlement amounts — Are dispute settlement amounts public int256[] calldata?

## Auditor claim

Medium severity. See [report §M-37](../report.md).

## Code references

`LiquidationResolutionFacet.sol:30,33; LiquidationFacetImpl.sol:367,370`

## Suggested test seam

Dispute resolution calldata inspection

## Auditor recommendation

Encrypted inputs or document as public

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
