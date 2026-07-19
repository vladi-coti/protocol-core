---
id: design-M-22-coti-dependencies
labels: [group:design-product, wayfinder:grilling]
priority: P1
finding: M-22
severity: Medium
status: open
disposition: defer
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
- [x] Fix disposition: `defer` (pin after signed forks merge to main)
- [ ] Pin `package.json` to commit SHAs + commit `yarn.lock` (stop gitignoring); then close ticket

## Answer

**Verdict: `valid`. Disposition: `defer` — ticket stays open until pin lands.**

Claim confirmed:
- `package.json` uses floating Git branches: `vladi-coti/coti-contracts#feat/signed`, `coti-ethers#extended-uint-support` (+ transitive SDK branch).
- Local `yarn.lock` already resolves those to commits, but `yarn.lock` / `package-lock.json` are **gitignored** — clean clones do not share the pin.
- `sim-coti-node` remains `file:../../coti/sim-coti-node` (local-only; out of remote pin scope for now).

### Policy (grilled 2026-07-19)

Keep branch refs while signed / extended-uint work is still on feature forks. **After those features merge into the upstream/main branches we consume**, pin:

1. `package.json` → `github:…#<immutableCommitSha>` (or published registry versions if available).
2. Stop ignoring and **commit `yarn.lock`** so CI/audit installs are reproducible.
3. Document resolved SHAs in the ticket / triage note at pin time.

Until then: accept install drift risk on purpose; do not pretend the lockfile is tracked.

### Implement brief (when unblocked)

- Edit `package.json` COTI github refs to SHAs of the merged main tips.
- Remove `yarn.lock` (and ideally `/package-lock.json`) from `.gitignore`; commit the lockfile used for audit/testnet builds.
- Optional: drop or document `file:` sim dep for remote CI.
- Static check: `test/audit/M22.test.ts` — `package.json` must not contain `#feat/` / `#extended-uint-support` branch refs; lockfile must be tracked.
