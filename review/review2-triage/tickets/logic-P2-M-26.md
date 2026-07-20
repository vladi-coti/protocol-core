---
id: logic-P2-M-26
labels: [group:logic-security, wayfinder:research]
priority: P2
finding: M-26
severity: Medium
status: closed
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-26: uint8 loop counters make large batches revert — Do batch loops revert when array length > 255?

## Auditor claim

Medium severity. See [report §M-26](../report.md).

## Code references

`MultiAccount.sol:295; PartyAFacet.sol:143; LibSettlement.sol:50` (+ ControlFacet / SymmioPartyB / LibSolvency / LibMuonSettlement / PartyAFacetImpl / LibPartyBQuoteActions)

## Suggested test seam

Batch test with 256+ entries

## Auditor recommendation

Use uint256 counters or explicit size caps

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Verdict:** `valid`  
**Disposition:** `implement` (done)

### Evidence

Red (pre-fix, Muon checks disabled):

```bash
python3 utils/update_sig_checks.py 1
npx hardhat test --network localSimCoti test/audit/M26.test.ts --grep "M-26"
# 4 passing — static uint8 present; addSymbols(2) OK; addSymbols(256) reverted; expireQuote(256) reverted
```

Green (post-fix):

```bash
npx hardhat test --network localSimCoti test/audit/M26.test.ts --grep "M-26"
# 3 passing — static uint256; addSymbols(2) OK; addSymbols(256) succeeds
```

### Implement brief

- Change unbounded batch `for (uint8 …)` → `for (uint256 …)` everywhere length is caller-controlled / unbounded.
- Files: `MultiAccount.sol`, `SymmioPartyB.sol`, `PartyAFacet.sol`, `PartyAFacetImpl.sol`, `ControlFacet.sol`, `LibSettlement.sol`, `LibSolvency.sol`, `LibPartyBQuoteActions.sol`, `LibMuonSettlement.sol`
- Regression: `test/audit/M26.test.ts`
