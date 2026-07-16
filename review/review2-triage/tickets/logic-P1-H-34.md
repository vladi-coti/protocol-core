---
id: logic-P1-H-34
labels: [group:logic-security, wayfinder:research]
priority: P1
finding: H-34
severity: High
status: closed
blocks: —
blocked_by: —
report: ../report.md
verdict: valid
disposition: implement
---

## Question

H-34: Expired close requests can still be force closed — Can force close execute after deadline if price window predates deadline?

## Auditor claim

High severity. See [report §H-34](../report.md).

## Code references

`PartyAFacetImpl.sol:224,249,256; ForceActionsFacetImpl.sol:82,84`

## Suggested test seam

test/ForceClosePosition.behavior.ts — force close after deadline

## Auditor recommendation

Require block.timestamp <= quote.deadline

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** Force close only checked `sig.endTime + forceCloseSecondCooldown <= quote.deadline`, not `block.timestamp <= quote.deadline`. Cancel-close expires when `now > deadline`, so stale force-close optionality survived past the deadline with a pre-deadline price window.

**Fix:** `require(block.timestamp <= quote.deadline, "PartyBFacet: Close request is expired")` in `ForceActionsFacetImpl.forceClosePosition`.

**Evidence:** dual PASS `test/audit/H34.test.ts`
