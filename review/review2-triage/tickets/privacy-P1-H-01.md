---
id: privacy-P1-H-01
labels: [group:privacy-leak, wayfinder:research, wayfinder:grilling]
priority: P1
finding: H-01
severity: High
status: closed
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

*(design notes — expand implications + change list below; validation/test still open)*

### Related tickets

**Same problem cluster (Muon / on-chain risk disclosure)** — option C or accept-leak (A) must account for these, not only `SingleUpnlSig.upnl`:

| Ticket | Why related |
| --- | --- |
| [privacy-P2-H-05](privacy-P2-H-05.md) | Liquidation stores UPNL / unrealized loss as plaintext snapshots (same risk data Muon carries). |
| [privacy-P3-M-47](privacy-P3-M-47.md) | Stale plaintext liquidation detail fields vs encrypted writes — leftover of mixed privacy model. |
| [privacy-P2-M-37](privacy-P2-M-37.md) | Dispute settlement amounts as plaintext `int256[]` calldata. |
| [privacy-P1-H-11](privacy-P1-H-11.md) | Settlement events publish opened/updated prices in plaintext (price disclosure after settle). |
| [privacy-P2-M-24](privacy-P2-M-24.md) | Emergency close emits close price plaintext — price public-by-design under preferred C for *mark* prices; confirm close price policy. |
| [privacy-P0-H-04](privacy-P0-H-04.md) | Force-close decrypts price predicates **before** Muon sig verify — ordering bug on Muon price path; fix ordering regardless of UPNL redesign. |
| [privacy-P3-M-34](privacy-P3-M-34.md) | Event type REALIZED_PNL_IN vs OUT leaks PnL direction even when amounts are private. |
| [logic-P0-H-16](logic-P0-H-16.md) | Deferred liquidation mixes Muon signed historical snapshot with current encrypted balance — Muon liquidation reshape touches this. |
| [logic-P2-M-15](logic-P2-M-15.md) | `priceValidTime` not enforced on price-bearing Muon paths — hygiene for price-only Muon. |
| [logic-P1-H-32](logic-P1-H-32.md) | Emergency close blocked when insolvent — uses pair UPNL sigs; call-site changes with on-chain UPNL. |

**Soft / consumer of outcome**

| Ticket | Why |
| --- | --- |
| [logic-P0-H-12](logic-P0-H-12.md) … [logic-P0-H-26](logic-P0-H-26.md) force-close / PartyB liq P0s | Many take Muon UPNL/price sigs; ABI + verify libs move under C. |
| Production checklist | [`../privx-production-checklist.txt`](../../privx-production-checklist.txt) — product Muon decision; keep in sync with this ticket. |

### Early product decisions (decide soon — not only this ticket)

These are the other “architecture / privacy boundary” calls. Deferring them late forces aegas/solver/Muon/proxy rework.

| Priority | Ticket | Decision | Why early |
| --- | --- | --- | --- |
| **Now** | **This ticket (H-01)** | Muon = prices only + on-chain UPNL vs accept public UPNL vs encrypt Muon UPNL | Touches ABI, Muon app, gas model, almost every solvency entrypoint. |
| **Now** | [design-H-13-free-collateral-privacy](design-H-13-free-collateral-privacy.md) | Free collateral / bridge / account **deltas** public vs encrypted | Gates [H-06](privacy-P1-H-06.md), [H-27](privacy-P1-H-27.md); aegas + solver account APIs. |
| **Now** | [design-M-13-observer-rotation](design-M-13-observer-rotation.md) | Observer key rotate: forward-only vs re-encrypt migrate | Proxy + indexer + solver read path; gates [M-14](privacy-P3-M-14.md), [M-44](privacy-P3-M-44.md). Do **not** solve H-01 by giving Muon the observer key. |
| Soon | [design-M-49-quote-metadata-privacy](design-M-49-quote-metadata-privacy.md) | Which quote metadata stays public (symbol/side/…) | Matching UX vs intent leak; gates [M-49](privacy-P3-M-49.md). |
| Soon | [design-M-16-liquidation-type-disclosure](design-M-16-liquidation-type-disclosure.md) | Public liquidation type (= deficit bucket leak?) intentional? | Gates [M-16](privacy-P3-M-16.md); smaller than H-01/H-13 but once public APIs ship it’s sticky. |
| Soon | [design-M-22-coti-dependencies](design-M-22-coti-dependencies.md) | Pin / publish COTI signed stack | Blocks every client (solver, aegas, proxy tooling); not a privacy leak per se but blocks mainnet. |

**Not an early crossroads (implement / fix ordering):** H-04 sig-before-predicate, most P0 logic exploits — do them as validated fixes; they don’t redefine the privacy product the way H-01 / H-13 / observer rotation do.

### Leak mechanism (valid on paper)

- Muon-backed txs pass structs with plaintext `int256 upnl` (and related pair/settlement UPNL arrays) in the public ABI (`SingleUpnlSig`, `SingleUpnlAndPriceSig`, `PairUpnlSig`, `PairUpnlAndPriceSig`, settlement/liquidation variants in `MuonStorage.sol`).
- `LibMuon*` hashes those plaintext values into the signed payload, then verifies TSS + gateway. The chain must see the number to verify — encrypting storage/events does not hide calldata.
- Flows: deallocate, sendQuote (upnl+price), PartyB lock/open/close, funding, settlement, force-close, liquidation / deferred.

### Who controls Muon (trust model)

- **Not one Symmio server.** Muon Network = distributed nodes running a MuonApp (`muon/symmio.js`). A gateway node + TSS subnet co-sign; diamond checks TSS pubkey + gateway ECDSA set by admin (`setMuonIds` / `MUON_SETTER_ROLE`).
- Protocol team chooses **which** app id / keys / gateway the diamond trusts and ships the **app code**. Node operators are Muon network participants, not “only Symmio.”
- Price feeds (e.g. Binance) are fetched off-chain by that app; UPNL today is **computed** off-chain from diamond open positions marked to those prices.

### Rejected: give all Muon nodes the private proxy / observer decrypt

Correctness alone (reading encrypted positions) suggests pointing Muon RPC at the decrypting proxy. **Do not** grant observer decrypt to the whole Muon fleet:

- Observer key ≈ decrypt every private book.
- Every TSS participant (and anyone who can induce them to call the proxy) sees global private state.
- Larger blast radius than intermittent plaintext UPNL in calldata.

Muon for prices does **not** need private RPC. Prefer architecture where Muon never holds observer access.

### Options

**Muon / oracle UPNL and prices in calldata**

**A — Keep plaintext signed UPNL/prices as today**  
Implication: private positions still leak PnL / risk via public Muon payloads. Faster to ship; weak privacy story for a “private” product.

**B — Redesign Muon (and verification) for private-compatible inputs**  
Implication: real privacy at the oracle edge (ciphertext / MPC attestation instead of `int256`), but off-chain Muon app + gateway work outside protocol-core; blocks claiming end-to-end private trading until done. Hard — Muon + diamond verify redesign together.

**C — Preferred: drop UPNL from Muon; compute UPNL on-chain**  
Implication: Muon stays a **simple public price oracle** — no encryption/decryption, no observer/proxy decrypt for Muon nodes. Protocol stops signing or verifying UPNL in Muon payloads; diamond computes UPNL in MPC from encrypted position storage using those prices. Real privacy at the cost of more on-chain gas and touching every UPNL call site.

| Option | Summary | Feasible? |
| --- | --- | --- |
| A — Accept leak | Keep plaintext UPNL in calldata; document as public risk | Yes — ship today |
| B — Private Muon I/O | Encrypt / attest Muon outputs + new verify | Hard — Muon + verify redesign |
| **C — Prices only + on-chain UPNL** | Strip UPNL from Muon; contract computes UPNL in MPC | Yes in principle; gas + every call site |

Other ideas considered and **not** preferred: privileged decrypting signer for Muon (concentrates observer trust); giving all Muon nodes proxy/observer decrypt (rejected above).

### Preferred direction (C) — expand this

**Idea:** Muon remains a **price oracle** (public mark prices are fine; no encrypt/decrypt in the Muon app). Drop UPNL from Muon calldata / hashes. Wherever the protocol today uses `upnlSig.upnl` (or party A/B UPNL fields), first **compute UPNL on-chain** from encrypted `openedPrice` / `quantity` / side (and any existing caps e.g. vs PartyB allocated that currently live in `muon/symmio.js`), then use that `gtInt256` in solvency/accounting.

**Why this fits PrivX better than A/B:**

- No observer key distribution to Muon nodes; Muon stays simple.
- No “encrypt like solver” Muon package that still needs a new on-chain verify scheme for signed private numbers (that is B).
- Gas is already very high on COTI MPC; incremental position loops are an honest cost of private accounting.
- A ships fast but sabotages the private product narrative.
**Implications to flesh out:**

1. **ABI / Muon app** — New (or narrowed) sig structs: price (+ timestamp, symbol/quote ids as needed) without `upnl`. Update `signParams` / methods in `muon/symmio.js`. Retarget diamond `LibMuon*` hash packing.
2. **On-chain UPNL helper** — Shared library: given party (+ PartyB where needed) and Muon prices map, iterate relevant open quotes, MPC compute aggregate UPNL (+ unrealized-loss style aggregates if still required). Must include the **full** relevant book or solvency is wrong/gameable.
3. **Call-site migration** — Every consumer of signed UPNL switches to “verify price sig → compute UPNL → proceed.” List below (starter; expand).
4. **Gas / position limits** — Define max opens or batching rules for COTI. Prototype one path (e.g. deallocate or sendQuote) on testnet before committing all paths.
5. **Related plaintext risk fields** — Liquidation / deferred / settlement still carry UPNL or loss snapshots in Muon structs and sometimes storage/views. Prefer C must cover those or they remain H-01-shaped leaks under other names.
6. **Muon ops** — Price-only Muon needs public RPC + market APIs only; **no** private proxy auth for Muon nodes.
7. **Product / marketing** — Until C (or B) ships, choosing A means claiming private DEX while broadcasting PnL on Muon txs.

### Starter change surface (expand)

**Storage / types**

- [ ] `contracts/storages/MuonStorage.sol` — strip or obsolete `upnl` / `upnlPartyA` / `upnlPartyB` / `upnlPartyBs` from structs that become price-only; liquidation/settlement variants.

**Verify libs**

- [ ] `LibMuon.sol`, `LibMuonAccount.sol`, `LibMuonPartyA.sol`, `LibMuonPartyB.sol`, `LibMuonFundingRate.sol`, `LibMuonSettlement.sol`, `LibMuonForceActions.sol`, `LibMuonLiquidation.sol` — hash without UPNL; price-only where applicable.

**Compute + use UPNL (replace `upnlSig.upnl*` inputs)**

- [ ] `LibAccount` available-balance helpers (partyA/B for quote / liquidation).
- [ ] `LibSolvency` — solvent after open/close using computed UPNL.
- [ ] `PartyAFacetImpl.sendQuote`
- [ ] `AccountFacetImpl` deallocate / PartyB deallocate / transferAllocation
- [ ] `PartyBQuoteActionsFacetImpl.lockQuote`
- [ ] `PartyBPositionActionsFacetImpl` open / fillClose / emergencyClose
- [ ] `PartyBGroupActions*` lockAndOpen paths
- [ ] `FundingRateFacetImpl.chargeFundingRate`
- [ ] `SettlementFacetImpl` / settlement Muon path
- [ ] `ForceActionsFacetImpl` / SettleAndForceClose (high-low currently includes party UPNLs)
- [ ] `LiquidationFacetImpl` / `DeferredLiquidationFacetImpl` (signed UPNL + total unrealized loss / allocated snapshots)

**Off-chain**

- [ ] `muon/symmio.js` (+ deploy/config) — price (and remaining public) methods; stop returning/signing UPNL for txs that move to C. No encrypt/decrypt path for Muon.
- [ ] Tests / solvers / aegas — stop packing dummy or real UPNL into calldata; supply price sigs only.
- [ ] Dummy sig helpers in `test/utils/SignatureUtils.ts`

**Non-goals for this preferred path**

- Do not grant Muon nodes observer/proxy decrypt for “so they can compute UPNL off-chain.”
- Do not treat “just encrypt UPNL in the Muon package like the solver” as sufficient without verify + ABI redesign (that is option B).

### Verdict / disposition

- Leak: **valid** — plaintext Muon UPNL/risk fields in calldata (confirmed via ABI + `H01` state-changing struct tests).
- Disposition: **implement** via option **C** (price-only Muon; on-chain MPC UPNL).
- Production cap: **`maxPartyAOpenPositions = 8`** (COTI testnet force-close @8 ≈114.4M gas; @10 fails ~116.3M / status 0).

### Option C implementation — gas

Prototype path 1: `deallocateWithQuotePrices(amount, QuotePriceSig)` verifies quote prices, computes PartyA UPNL on-chain from encrypted open positions, then reuses deallocate solvency/accounting.

Prototype path 2: `forceClosePositionWithQuotePrices(...)` keeps the force-close flow but computes both PartyA full-book UPNL and PartyB pair-book UPNL on-chain from price-only quote sigs before the close-solvency check. This is the better max-open-position sizing harness because `deallocate` only exercises PartyA accounting and is an optimistic lower bound.

Full implementation path: normal state-changing Muon calldata structs no longer carry plaintext `upnl`, `upnlPartyA`, `upnlPartyB`, `upnlPartyBs`, or `totalUnrealizedLoss`. Solidity verifies price-only payloads and computes UPNL/loss aggregates from encrypted quote state in `LibOnChainUpnl`.

Sim (`localSimCoti`) result:

Deallocate:

| open positions | baseline signed-UPNL gas | computed-UPNL gas |
| --- | ---: | ---: |
| 0 | 3,344,997 | 6,781,962 |
| 1 | 3,492,297 | 9,053,380 |
| 5 | 3,492,297 | 17,305,155 |
| 10 | 3,492,297 | 27,617,764 |

Force close:

| open positions | baseline signed-UPNL gas | computed-UPNL gas |
| --- | ---: | ---: |
| 1 | 24,088,890 | 28,190,099 |
| 5 | 24,477,090 | 45,024,410 |
| 10 | 24,477,090 | 65,586,011 |

Deallocate rough slope: ~6.8M base + ~2.1M per open position.
Force-close rough slope: ~24M base + ~4.2M per open position after the first quote. At 10 positions, sim already reaches ~65.6M gas, so deallocate is too weak for cap sizing.

Temporary read: if testnet agrees with sim, a 10-open-position cap is probably too high for the worst affected one-tx flow. Need testnet force-close sample before setting the production max.

COTI testnet sample for 10 open positions failed before producing a successful force-close gas number:

- Command: `npx hardhat test --network coti-testnet test/audit/H01.test.ts --grep "H-01 gas: force-close baseline vs computed UPNL with 10 open positions"`
- Result: failed transaction, status `0`, `gasUsed=116,282,373`.
- Read: 10 open positions is not viable for the worst affected one-tx path on testnet. The cap should be materially lower, or the flow must be batched/redesigned.

Full migration sim (`localSimCoti`) result after moving normal call sites to price-only:

Deallocate:

| open positions | `deallocate` price-only gas | `deallocateWithQuotePrices` alias gas |
| --- | ---: | ---: |
| 0 | 6,802,100 | 6,782,240 |
| 1 | 9,073,770 | 9,053,906 |
| 5 | 17,326,555 | 17,306,673 |
| 10 | 27,640,426 | 27,620,522 |

Force close:

| open positions | normal `forceClosePosition` price-only gas | alias gas |
| --- | ---: | ---: |
| 1 | 28,192,627 | 28,192,610 |
| 5 | 45,026,754 | 45,026,737 |
| 10 | 65,588,125 | 65,588,108 |

Targeted command:

```bash
npx hardhat test --network localSimCoti test/audit/H01.test.ts --grep "H-01"
```

Result: `8 passing`.

### Cap decision (testnet)

| open positions | network | force-close result |
| --- | --- | --- |
| 10 | coti-testnet | FAIL — `gasUsed≈116.3M`, status 0 |
| 8 | coti-testnet | PASS — `gasUsed≈114.4M` (openPosition@8 ≈98M) |

Implemented: `MAStorage.maxPartyAOpenPositions`, enforced in `LibQuote.addToOpenPositions`, setter `ControlFacet.setMaxPartyAOpenPositions`, view `ViewFacet.maxPartyAOpenPositions`. Fixture + `scripts/Initialize.ts` set **8**. H01 gas benches raise the cap when counting past 8.

### Implement brief

- Price-only Muon structs; `LibOnChainUpnl` computes PartyA/PartyB UPNL and liquidation aggregates from encrypted quote state.
- Normal call sites (account / open / close / settle / force-close / funding / liquidation) consume price-only sigs.
- Liquidation detail UPNL / totalUnrealizedLoss stored encrypted (`utInt256`).
- Code-size: extract force-close helpers in `ForceActionsFacetImpl`; delete oversized `PartyBGroupActionsFacetImpl` and link shared `PartyBPositionActionsFacetImpl.openPosition` into Group/Position facets.
- Regression: `test/audit/H01.test.ts` (leak + gas); dual-run row in `test-runs/sim-vs-testnet.md`.

### Next (follow-ons, not blocking this ticket)

1. Broader suite beyond H-01 (Account / ForceClose / Settlement / Liquidation behaviors) as capacity allows.
2. Related tickets in the Muon/privacy cluster (H-05, M-47, etc.) still own their own leftovers.
