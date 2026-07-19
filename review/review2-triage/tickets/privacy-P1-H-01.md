---
id: privacy-P1-H-01
labels: [group:privacy-leak, wayfinder:research, wayfinder:grilling]
priority: P1
finding: H-01
severity: High
status: closed
verdict: valid
disposition: implement
blocks: privacy-P2-H-05, privacy-P3-M-47 (soft — shared risk snapshot privacy)
blocked_by: —
report: ../report.md
related: >
  Same Muon / risk-privacy cluster: privacy-P2-H-05, privacy-P3-M-47,
  privacy-P2-M-37, privacy-P1-H-11, privacy-P2-M-24, privacy-P0-H-04,
  privacy-P3-M-34, logic-P0-H-16, logic-P2-M-15, logic-P1-H-32.
  Sibling early decisions (separate): design-H-13-free-collateral-privacy,
  design-M-13-observer-rotation, design-M-49-quote-metadata-privacy,
  design-M-16-liquidation-type-disclosure, design-M-22-coti-dependencies.
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

- [x] Read cited code paths in current branch (check review1 overlap)
- [x] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [x] Run test; record command + output
- [x] Verdict: `valid`
- [x] Fix disposition: `implement`
- [x] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

**Valid.** State-changing Muon calldata structs carried plaintext `int256 upnl` / pair UPNL arrays / `totalUnrealizedLoss`. Verifying those hashes required the numbers on-chain — encrypting storage/events did not hide calldata.

**Disposition: implement option C** — Muon = **price oracle only**; diamond computes UPNL/loss in MPC from encrypted quote state (`LibOnChainUpnl`). Done on-chain + in-repo Muon app.

### Evidence (closed)

| Check | Result |
| --- | --- |
| State-changing Muon structs have no `upnl` / `upnlPartyA\|B\|s` / plaintext `totalUnrealizedLoss` | Pass — `MuonStorage.sol`; H01 ABI test |
| Call sites use `LibOnChainUpnl`, not signed UPNL | Pass — account / sendQuote / lock / open / close / funding / settlement / force-close / liquidation / deferred |
| Liq detail UPNL + totalUnrealizedLoss encrypted (`utInt256`) | Pass — `AccountStorage.LiquidationDetail` |
| Production open-position cap | **8** — testnet force-close @8 ≈114.4M gas PASS; @10 FAIL (`gasUsed≈116.3M`) |
| In-repo Muon app strips UPNL from response + `signParams` | Pass — `muon/symmio.js` `delete result.uPnl` / price-only hashes |
| Regression suite | `test/audit/H01.test.ts` — leak, correctness (double-count, loss sign, deallocate), gas |
| Broader audit after H-01 migration fixes | `test/audit/*.test.ts` on `localSimCoti`: **37 passing** (2026-07-19) |
| Dual-run | [`../test-runs/sim-vs-testnet.md`](../test-runs/sim-vs-testnet.md) — H-01 @8 PASS/PASS; @10 PASS/FAIL |

Post-migration correctness fixes locked in with this ticket:

- COTI `mux(bit,a,b)=bit?b:a` arms for on-chain UPNL profit/loss (`LibOnChainUpnl`)
- Same mux fix for `partyAAvailableForQuote` / `partyBAvailableForQuote` (`LibAccount`) — +UPNL must lift deallocate
- Open-position solvency no longer double-counts entry→mark delta (`LibSolvency`)
- Deferred `liquidationAllocatedBalance` kept public (H-16) and used for prove + type class

### Soft leftovers (do **not** reopen H-01)

| Item | Owner |
| --- | --- |
| Struct/fn names still say `*Upnl*` while payloads are prices | rename pass / follow-up |
| Test builders still accept unused `upnl` params (`void upnl`) | harness cleanup |
| `LiquidationDetail.partyAAccumulatedUpnl` always `0` plaintext husk | [privacy-P2-H-05](privacy-P2-H-05.md) / [privacy-P3-M-47](privacy-P3-M-47.md) |
| Production Muon network must deploy updated `muon/symmio.js` | ops / deploy checklist |
| Related cluster tickets (H-05, M-47, H-11, …) | their own tickets |

### Implement brief

- Price-only Muon structs; `LibOnChainUpnl` computes PartyA/PartyB UPNL and liquidation loss aggregates.
- Normal call sites consume price-only sigs → compute UPNL → solvency/accounting.
- Liquidation detail UPNL / totalUnrealizedLoss stored encrypted (`utInt256`).
- Cap: `MAStorage.maxPartyAOpenPositions = 8` (fixture + `scripts/Initialize.ts`).
- Regression: `test/audit/H01.test.ts`; dual-run rows in `test-runs/sim-vs-testnet.md`.

### Change surface (done)

**Storage / types**

- [x] `contracts/storages/MuonStorage.sol` — strip plaintext UPNL/loss from state-changing Muon structs (`liquidationAllocatedBalance` retained for H-16)

**Verify libs**

- [x] `LibMuon*.sol` — hash price/quote (or symbol) fields only; no UPNL ints

**Compute + use UPNL**

- [x] `LibOnChainUpnl` + `LibAccount` / `LibSolvency` available-balance & open/close solvency
- [x] `PartyAFacetImpl.sendQuote`
- [x] `AccountFacetImpl` deallocate / PartyB deallocate / transferAllocation
- [x] `PartyBQuoteActionsFacetImpl.lockQuote`
- [x] `PartyBPositionActionsFacetImpl` open / fillClose / emergencyClose (+ Group → shared open/lock)
- [x] `FundingRateFacetImpl.chargeFundingRate`
- [x] `SettlementFacetImpl` / settlement Muon path
- [x] `ForceActionsFacetImpl` / SettleAndForceClose
- [x] `LiquidationFacetImpl` / `DeferredLiquidationFacetImpl`

**Off-chain**

- [x] `muon/symmio.js` — strip UPNL from `onRequest` results; `signParams` price/quote only
- [x] Dummy sig helpers in `test/utils/SignatureUtils.ts` (unused upnl params ignored)
- [x] Audit / model helpers supply price sigs only

### Cap / gas (reference)

Full-migration sim force-close ~28M / ~45M / ~66M at 1 / 5 / 10 opens. Testnet sets production cap at **8** (see dual-run table).

Targeted:

```bash
TEST_MODE=static npx hardhat test --network localSimCoti test/audit/H01.test.ts --grep "H-01"
TEST_MODE=static npx hardhat test --network localSimCoti test/audit/*.test.ts   # 37 passing
```

---

## Background (design record — closed)

Kept for cross-ticket context. Product decision was **C**; A/B rejected for PrivX.

### Related tickets

**Same problem cluster (Muon / on-chain risk disclosure)**

| Ticket | Why related |
| --- | --- |
| [privacy-P2-H-05](privacy-P2-H-05.md) | Liquidation stores UPNL / unrealized loss as plaintext snapshots (same risk data Muon carried). |
| [privacy-P3-M-47](privacy-P3-M-47.md) | Stale plaintext liquidation detail fields vs encrypted writes. |
| [privacy-P2-M-37](privacy-P2-M-37.md) | Dispute settlement amounts as plaintext `int256[]` calldata. |
| [privacy-P1-H-11](privacy-P1-H-11.md) | Settlement events publish opened/updated prices in plaintext. |
| [privacy-P2-M-24](privacy-P2-M-24.md) | Emergency close emits close price plaintext. |
| [privacy-P0-H-04](privacy-P0-H-04.md) | Force-close decrypts price predicates before Muon sig verify. |
| [privacy-P3-M-34](privacy-P3-M-34.md) | Event type REALIZED_PNL_IN vs OUT leaks PnL direction. |
| [logic-P0-H-16](logic-P0-H-16.md) | Deferred liquidation signed allocated snapshot (retained under C). |
| [logic-P2-M-15](logic-P2-M-15.md) | `priceValidTime` hygiene for price-only Muon. |
| [logic-P1-H-32](logic-P1-H-32.md) | Emergency close uses pair price sigs + on-chain UPNL. |

### Options (decision)

| Option | Summary | Chosen? |
| --- | --- | --- |
| A — Accept leak | Keep plaintext UPNL in calldata | No |
| B — Private Muon I/O | Encrypt / attest Muon outputs | No — off-chain redesign |
| **C — Prices only + on-chain UPNL** | Strip UPNL from Muon; contract computes UPNL in MPC | **Yes — implemented** |

Rejected: grant Muon nodes observer/proxy decrypt so they can compute UPNL off-chain.
