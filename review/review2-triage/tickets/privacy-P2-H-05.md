---
id: privacy-P2-H-05
labels: [group:privacy-leak, wayfinder:research]
priority: P2
finding: H-05
severity: High
status: open
blocks: —
blocked_by: —
report: ../report.md
---

## Question

H-05: PartyA liquidation exposes plaintext risk snapshots — Are UPNL/unrealized loss plaintext in LiquidationDetail? (Check report5#3 partial fix)

## Auditor claim

High severity. See [report §H-05](../report.md).

## Code references

`AccountStorage.sol:29,32; LiquidationFacetImpl.sol:128,131`

## Suggested test seam

Liquidation tx + getLiquidatedStateOfPartyA inspection

## Auditor recommendation

Remove plaintext fields or encrypt

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
