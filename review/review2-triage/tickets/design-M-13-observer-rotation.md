---
id: design-M-13-observer-rotation
labels: [group:design-product, wayfinder:grilling]
priority: P1
finding: M-13
severity: Medium
status: closed
disposition: implement
blocks: —
blocked_by: —
report: ../report.md
---

## Question

M-13: Decide trusted observer rotation model — Is forward-only rotation acceptable or is migration required?

## Auditor claim

Medium severity. See [report §M-13](../report.md).

## Code references

`ControlFacet.sol:527,533; LibEncryption.sol:34,47; ViewFacet.sol:460,466`

## Suggested test seam

N/A — grilling session

## Auditor recommendation

Migration process or document forward-only

## Resolution checklist

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1 — N/A (grilling/design ticket)
- [x] Run test; record command + output — N/A
- [x] Verdict: `valid` (auditor claim confirmed in code: setter only redirects future `offBoardToObserver`; no observer migration path exists, unlike user-key rotation in `LibAccountEncryption.setEncryptionAddress`)
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (below)
- [x] Implement migrator + regression test; then close ticket

## Answer

**Verdict: `valid`. Disposition: `implement` (done).**

Decision: **on-chain batched migration**, not forward-only documentation.

### Agreed design (grilled 2026-07-19)

1. **Flip-first cutover.** `setTrustedObserverAddress` flips immediately; admin then runs batched re-encrypt until catch-up. Writes during migration already target the new observer, so overlap is harmless.
2. **Admin-only migrator** (`DEFAULT_ADMIN_ROLE`). Migration is ops, not a user feature.
3. **No new registry storage.** Admin passes `address[] partyAs` built off-chain (events/indexer). Caller is trusted, so list completeness is an ops concern, not a contract invariant.
4. **Batch unit: PartyA page.** `migrateObserverForPartyA(partyA, quoteStart, quoteLimit)` — account-header observer slots once (allocated/locked/pending, reserve, fee collector, reimbursement, liq deficit+fee, settlement states) + a slice of that PartyA's quotes.
5. **Active quotes only** (pending + opened + in-flight close/liq-pending). Closed/canceled/expired/liquidated observer ciphertext stays stale — dead-quote history remains readable only to the old observer key.
6. **PartyB side derived from quotes.** Counterparty `observerPartyB*` maps and settlement states migrate inline from the PartyA's active quotes; `migrateObserverForPartyBs(address[])` for PartyB-only slots (reserve vault, fee collector).
7. **Idempotent, lock-free.** Migrator is a pure re-offboard from primary user ciphertext (old observer key never needed — same pattern as `LibAccountEncryption`). Re-runs and races with user txs converge; only cost is redundant gas.

### Landed

- `LibAccountEncryption.migrateObserverForPartyA` / `migrateObserverForPartyBs`
- `ControlFacet` + `IControlFacet` admin wrappers; ControlFacet linked to `LibAccountEncryption` in deploy
- Regression: `test/audit/M13.test.ts` — flip observer, migrate page, new observer decrypts allocated/quote/PartyB alloc; non-admin reverts. Sim PASS.
