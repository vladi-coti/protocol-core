---
id: design-M-22-coti-dependencies
labels: [group:design-product, wayfinder:grilling]
priority: P1
finding: M-22
severity: Medium
status: closed
disposition: fix
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-22: Decide COTI dependency pinning policy — Are COTI deps pinned to immutable commits?

## Auditor claim

Medium severity. See [report §M-22](../report.md).

## Code references

`package.json:10,11; .gitignore:2`

## Suggested test seam

Compare package.json refs vs lockfile presence

## Auditor recommendation

Pin to commits; track lockfile in repo

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1 — N/A (design; local lockfile/git refs are the evidence)
- [x] Run test; record command + output — N/A (static proof below)
- [x] Verdict: `valid`
- [x] Fix disposition: `fix` (exact published registry pins; lockfile stays gitignored)
- [x] Pin `package.json` to immutable versions; close ticket

## Answer

**Verdict: `valid`. Disposition: `fix` — pinned 2026-07-22.**

Claim confirmed on floating Git / `link:` refs. Remediation:

| Package | Pin | Notes |
| --- | --- | --- |
| `@coti-io/coti-contracts` | `1.3.1` | npm registry (signed MPC); npm `gitHead` `33ee5324f8a970a9b060af53ded957886f4d89d3` |
| `@coti-io/coti-ethers` | `1.0.6` | npm registry (exact) |

**Lockfile policy (deliberate):** keep `yarn.lock` gitignored. Exact semver pins in `package.json` are the reproducibility control we accept; tracking the full lockfile is out of scope for this privacy/audit branch (hygiene, not a privacy change).

### Static tripwire

`npx hardhat test test/audit/M22.test.ts --network hardhat` (static; asserts exact pins + no branch/`link:` refs).
