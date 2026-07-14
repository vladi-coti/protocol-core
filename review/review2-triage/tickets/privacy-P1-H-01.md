---
id: privacy-P1-H-01
labels: [group:privacy-leak, wayfinder:research]
priority: P1
finding: H-01
severity: High
status: open
blocks: design-M-22-coti-dependencies (soft — Muon arch may be out of repo)
blocked_by: design-M-22-coti-dependencies
report: ../report.md
---

## Question

H-01: Muon UPNL signatures expose private PnL as plaintext calldata — Are UPNL/unrealized loss in public Muon calldata structs?

## Auditor claim

High severity. See [report §H-01](../report.md).

## Code references

`MuonStorage.sol:20,23; LibMuonAccount.sol:24; LibMuonSettlement.sol:37`

## Suggested test seam

Inspect tx calldata on deallocation/settlement/liquidation flows

## Auditor recommendation

Encrypt inputs or classify as public; Muon redesign likely needed

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
