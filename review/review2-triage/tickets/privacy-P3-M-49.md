---
id: privacy-P3-M-49
labels: [group:privacy-leak, wayfinder:research]
priority: P3
finding: M-49
severity: Medium
status: open
blocks: design-M-49-quote-metadata-privacy
blocked_by: design-M-49-quote-metadata-privacy
report: ../report.md
---

## Question

M-49: Public quote metadata leaks private trading intent — Are symbol/side/orderType/deadline/whitelist public while amounts encrypted?

## Auditor claim

Medium severity. See [report §M-49](../report.md).

## Code references

`QuoteStorage.sol:69,70; PartyAFacet.sol:22,64; ViewFacet.sol:456`

## Suggested test seam

Quote creation calldata + view inspection

## Auditor recommendation

See design-M-49 for privacy scope decision

## Resolution checklist

- [ ] Read cited code paths in current branch (check review1 overlap)
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(unresolved)*
