---
id: privacy-P1-H-01
labels: [group:privacy-leak, wayfinder:research, wayfinder:grilling]
priority: P1
finding: H-01
severity: High
status: open
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
- [ ] Build red-capable testnet test per **diagnosing-bugs** Phase 1
- [ ] Run test; record command + output
- [ ] Verdict: `valid` | `invalid` | `partial` | `design-choice`
- [ ] Fix disposition: `implement` | `defer` | `wontfix` | `needs-human`
- [ ] If valid: write implement brief (minimal fix, affected files, regression test name)

## Answer

*(design notes — expand implications + change list below; validation/test still open)*

### Related tickets

**Same problem cluster (Muon / on-chain risk disclosure)** — option D or accept-leak must account for these, not only `SingleUpnlSig.upnl`:

| Ticket | Why related |
| --- | --- |
| [privacy-P2-H-05](privacy-P2-H-05.md) | Liquidation stores UPNL / unrealized loss as plaintext snapshots (same risk data Muon carries). |
| [privacy-P3-M-47](privacy-P3-M-47.md) | Stale plaintext liquidation detail fields vs encrypted writes — leftover of mixed privacy model. |
| [privacy-P2-M-37](privacy-P2-M-37.md) | Dispute settlement amounts as plaintext `int256[]` calldata. |
| [privacy-P1-H-11](privacy-P1-H-11.md) | Settlement events publish opened/updated prices in plaintext (price disclosure after settle). |
| [privacy-P2-M-24](privacy-P2-M-24.md) | Emergency close emits close price plaintext — price public-by-design under preferred D for *mark* prices; confirm close price policy. |
| [privacy-P0-H-04](privacy-P0-H-04.md) | Force-close decrypts price predicates **before** Muon sig verify — ordering bug on Muon price path; fix ordering regardless of UPNL redesign. |
| [privacy-P3-M-34](privacy-P3-M-34.md) | Event type REALIZED_PNL_IN vs OUT leaks PnL direction even when amounts are private. |
| [logic-P0-H-16](logic-P0-H-16.md) | Deferred liquidation mixes Muon signed historical snapshot with current encrypted balance — Muon liquidation reshape touches this. |
| [logic-P2-M-15](logic-P2-M-15.md) | `priceValidTime` not enforced on price-bearing Muon paths — hygiene for price-only Muon. |
| [logic-P1-H-32](logic-P1-H-32.md) | Emergency close blocked when insolvent — uses pair UPNL sigs; call-site changes with on-chain UPNL. |

**Soft / consumer of outcome**

| Ticket | Why |
| --- | --- |
| [logic-P0-H-12](logic-P0-H-12.md) … [logic-P0-H-26](logic-P0-H-26.md) force-close / PartyB liq P0s | Many take Muon UPNL/price sigs; ABI + verify libs move under D. |
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

| Option | Summary | Feasible? |
| --- | --- | --- |
| A — Accept leak | Keep plaintext UPNL in calldata; document as public risk | Yes — ship today |
| B — Encrypt UPNL in Muon/output + new verify | Ciphertext / MPC attestation instead of int256 | Hard — Muon + diamond verify redesign together |
| C — Privileged decrypting signer | Observer-like component signs / posts encrypted UPNL | Feasible — concentrates trust in our infra |
| **D — Preferred: Muon prices only; UPNL on-chain in MPC** | Public prices OK; contract computes UPNL from encrypted position storage before use | Yes in principle; gas + touch every UPNL call site |

### Preferred direction (D) — expand this

**Idea:** Muon remains a **price oracle** (public mark prices are fine). Drop UPNL from Muon calldata / hashes. Wherever the protocol today uses `upnlSig.upnl` (or party A/B UPNL fields), first **compute UPNL on-chain** from encrypted `openedPrice` / `quantity` / side (and any existing caps e.g. vs PartyB allocated that currently live in `symmio.js`), then use that `gtInt256` in solvency/accounting.

**Why this fits PrivX better than B/C:**

- No observer key distribution to Muon nodes.
- No “encrypt like solver” Muon package that still needs a new on-chain verify scheme for signed plaintext numbers.
- Gas is already very high on COTI MPC; incremental position loops are an honest cost of private accounting.

**Implications to flesh out:**

1. **ABI / Muon app** — New (or narrowed) sig structs: price (+ timestamp, symbol/quote ids as needed) without `upnl`. Update `signParams` / methods in `muon/symmio.js`. Retarget diamond `LibMuon*` hash packing.
2. **On-chain UPNL helper** — Shared library: given party (+ PartyB where needed) and Muon prices map, iterate relevant open quotes, MPC compute aggregate UPNL (+ unrealized-loss style aggregates if still required). Must include the **full** relevant book or solvency is wrong/gameable.
3. **Call-site migration** — Every consumer of signed UPNL switches to “verify price sig → compute UPNL → proceed.” List below (starter; expand).
4. **Gas / position limits** — Define max opens or batching rules for COTI. Prototype one path (e.g. deallocate or sendQuote) on testnet before committing all paths.
5. **Related plaintext risk fields** — Liquidation / deferred / settlement still carry UPNL or loss snapshots in Muon structs and sometimes storage/views. Prefer D must cover those or they remain H-01-shaped leaks under other names.
6. **Muon ops** — Price-only Muon needs public RPC + market APIs only; **no** private proxy auth for Muon nodes.
7. **Product / marketing** — Until D (or B/C) ships, choosing A means claiming private DEX while broadcasting PnL on Muon txs.

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

- [ ] `muon/symmio.js` (+ deploy/config) — price (and remaining public) methods; stop returning/signing UPNL for txs that move to D.
- [ ] Tests / solvers / aegas — stop packing dummy or real UPNL into calldata; supply price sigs only.
- [ ] Dummy sig helpers in `test/utils/SignatureUtils.ts`

**Non-goals for this preferred path**

- Do not grant Muon nodes observer/proxy decrypt for “so they can compute UPNL off-chain.”
- Do not treat “just encrypt UPNL in the Muon package like the solver” as sufficient without verify + ABI redesign (that is option B).

### Verdict / disposition (pending)

- Leak: treat as **valid** once calldata inspection / one live tx confirms (checklist still open).
- Disposition leaning: **implement** via option **D** (needs-human for gas limits + liquidation/settlement aggregate design), not accept-as-public unless product explicitly chooses A.

### Next

1. Confirm on testnet one Muon-backed tx shows plaintext UPNL in calldata (evidence for checklist).
2. Spike: price-only Muon + on-chain UPNL for `sendQuote` or `deallocate` — measure gas vs position count.
3. Expand change surface + Muon method matrix (which methods stay, which die).
4. Decide liquidation/settlement aggregates (on-chain only vs still signed public — if public, document as accepted leak).
