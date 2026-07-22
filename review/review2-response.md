# Review2 response

Response to the findings in [`report.md`](report.md) (50 items). Each entry states what we concluded, what changed (or why not), and where to verify.

## Summary

| Bucket | Count |
| --- | --- |
| Fixed | 33 |
| Won't fix (design-choice or accepted) | 13 |
| Invalid / superseded | 4 |
| **Total** | **50** |

### Product decisions that gate privacy scope

- **[H-13](report.md#h-13-deposited-free-collateral-and-bridge-amounts-remain-plaintext)** — free collateral / bridge / allocate amounts stay **public** until private tokens.
- **[H-01](report.md#h-01-muon-upnl-signatures-expose-private-pnl-as-plaintext-calldata)** — Muon supplies public prices only; UPNL is computed on-chain in MPC (never as Muon plaintext). Caps concurrent PartyA opens at **8** for gas.
- **[M-13](report.md#m-13-trusted-observer-rotation-does-not-re-encrypt-existing-observer-state)** — on observer rotation, switch the active observer first, then admin-migrate historical ciphertext; missing observer events mean clients should poll views ([M-14](report.md#m-14-observer-balance-change-events-are-missing-for-non-accounting-balance-mutations) / [M-40](report.md#m-40-trusted-observer-events-are-missing-for-position-execution)).
- **[M-49](report.md#m-49-public-quote-metadata-leaks-private-trading-intent)** — encrypt quote sizes/prices/balances; leave routing/intent metadata public.
- **[M-16](report.md#m-16-public-liquidation-type-leaks-the-private-deficit-range)** — liquidation type stays public.

### Out of scope (explicit)

- Granting Muon network participants observer/proxy decrypt (rejected under the H-01 Muon design above).
- Encrypting free-collateral / bridge / allocate amounts without private tokens (H-13).

## Fixed

### [C-01](report.md#c-01-unsigned-encrypted-values-can-become-negative-in-signed-solvency-math) — Unsigned encrypted values can become negative in signed solvency math

- **Severity:** Critical
- **Verdict:** `valid`
- **Disposition:** `fixed`

Unsigned encrypted quote/balance inputs were cast into signed MPC math without proving `value < 2^255`, so an oversized ciphertext could appear negative and invert solvency. We added `toNonNegativeSigned` (and swept remaining `.toSigned()` sites in quote/settlement/funding/force/liquidation paths) so out-of-range values revert instead of wrapping into signed space.

Evidence: `test/audit/C01.test.ts`.

### [H-01](report.md#h-01-muon-upnl-signatures-expose-private-pnl-as-plaintext-calldata) — Muon UPNL signatures expose private PnL as plaintext calldata

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Muon calldata previously carried plaintext UPNL / unrealized-loss fields, bypassing on-chain encryption for the same risk numbers. Keeping those values public was unacceptable; encrypting Muon I/O (or giving Muon nodes observer/proxy decrypt so they can compute UPNL off-chain) would have required a larger off-chain redesign we did not want. Instead Muon is a **public price oracle only**, and the diamond computes UPNL in MPC from encrypted quote state (`LibOnChainUpnl`).

That on-chain loop costs gas proportional to open positions. Worst case is force-close (prices + UPNL over the full book): on COTI testnet, **8** open positions completed under the ~120M gas block limit (~114.4M), while **10** failed (~116.3M gas used / OOG). Production therefore caps concurrent PartyA opens via `maxPartyAOpenPositions = 8` (`ControlFacet.setMaxPartyAOpenPositions`). Deallocate and other price+UPNL paths are cheaper than force-close but share the same scaling.

Evidence: `test/audit/H01.test.ts`.

### [H-02](report.md#h-02-signed-mpc-accounting-uses-unchecked-arithmetic) — Signed MPC accounting uses unchecked arithmetic

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Core signed accounting used unchecked `gtInt256` add/sub, which can wrap at the signed boundary and corrupt balances or solvency branches. Accounting paths now use `checkedAdd` / `checkedSub` (struct locked-value helpers excepted where intentionally unchecked).

Evidence: `test/audit/H02.test.ts`.

### [H-04](report.md#h-04-force-close-price-checks-run-before-muon-signature-verification) — Force-close price checks run before Muon signature verification

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Force-close decrypted private close-price predicates and branched on reverts **before** authenticating the Muon high/low signature, creating a revert oracle. Verification now runs first; private onboard/decrypt only follows a valid sig.

Evidence: `test/audit/H04.test.ts`.

### [H-08](report.md#h-08-account-balance-checks-expose-threshold-oracles-through-revert-order) — Account balance checks expose threshold oracles through revert order

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

`allocate` / `internalTransfer` decrypted the allocated-balance limit before checking plaintext free balance, so revert order leaked whether the encrypted limit would fail. Public free-balance checks now run first; allocated-limit decrypt only after the public gate passes.

Evidence: `test/audit/H08.test.ts`.

### [H-11](report.md#h-11-settlement-events-publish-encrypted-opened-prices-in-plaintext) — Settlement events publish encrypted opened prices in plaintext

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

`SettleUpnl` emitted opened/updated prices in plaintext despite encrypted quote storage. We stripped `updatedPrices` (and related plaintext price payload) from that event so settlement logs no longer publish those values.

Evidence: `test/audit/H11.test.ts`.

### [H-12](report.md#h-12-settleandforcecloseposition-settles-against-the-caller-instead-of-the-quote-partya) — `settleAndForceClosePosition` settles against the caller instead of the quote PartyA

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

`settleAndForceClosePosition` settled against `msg.sender` instead of the quote’s PartyA, so a third party could not complete a valid settle+force-close for the position owner. Settlement now always targets `quote.partyA`.

Evidence: `test/audit/H12.test.ts`.

### [H-14](report.md#h-14-force-close-liquidation-ignores-reserve-credit-when-computing-partyb-deficit) — Force-close liquidation ignores reserve credit when computing PartyB deficit

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Force-close credited reserve into PartyB allocated, then liquidated using a pre-credit available figure, so insolvency after reserve unlock could be missed. Liquidation now uses post-reserve available (`gtWithReserve`).

Evidence: `test/audit/H14.test.ts`.

### [H-15](report.md#h-15-partyb-liquidation-can-revert-when-remaining-lf-exceeds-allocated-balance) — PartyB liquidation can revert when remaining LF exceeds allocated balance

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

PartyB liquidation could compute `remainingLf` larger than allocated and revert on `checkedSub`, blocking liquidation. We cap `remainingLf` to PartyB allocated before subtracting.

Evidence: `test/audit/H15.test.ts`.

### [H-16](report.md#h-16-deferred-liquidation-type-uses-current-balance-instead-of-the-signed-snapshot) — Deferred liquidation type uses current balance instead of the signed snapshot

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Deferred liquidation mixed a signed historical insolvency snapshot with **current** allocated/availability for type selection and reimbursement, allowing drift to change outcomes. Type and reimbursement now both use the signed allocated snapshot.

Evidence: `test/audit/H16.test.ts`.

### [H-26](report.md#h-26-force-close-partyb-liquidation-uses-a-post-close-balance-without-closing-the-quote) — Force-close PartyB liquidation uses a post-close balance without closing the quote

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Force-close insolvency liquidation used a post-close available that unlocked the closing quote’s cva+lf in the numerator without actually releasing those locks on PartyB, mismatching solvency vs liquidation. We unlock closed-quote cva+lf on PartyB locks before `liquidatePartyBFromAvailable`.

Evidence: `test/audit/H26.test.ts`.

### [H-28](report.md#h-28-quote-views-expose-coti-system-ciphertexts) — Quote views expose COTI system ciphertexts

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Public quote getters returned storage `Quote` / `utUint256` system ciphertexts that network key holders (or mistaken client decrypt) could misuse. Public views now return `ViewQuote` with user-facing `ctUint256` only.

Evidence: `test/audit/H28.test.ts`.

### [H-33](report.md#h-33-fee-distributor-cannot-claim-encrypted-fee-accruals) — Fee distributor cannot claim encrypted fee accruals

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Fees accrued into encrypted collector balances while `SymmioFeeDistributor.claimAllFee` only did ERC-20 `balanceOf` + withdraw, so encrypted accruals were stuck. Collector claim now pulls encrypted fee balances before distributor withdraw.

Evidence: `test/audit/H33.test.ts`.

### [H-34](report.md#h-34-expired-close-requests-can-still-be-force-closed-after-their-deadline) — Expired close requests can still be force closed after their deadline

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Force close checked cooldown against `quote.deadline` but not `block.timestamp <= quote.deadline`, so expired close requests could still be force-closed. Force close now requires the quote deadline to still be in the future.

Evidence: `test/audit/H34.test.ts`.

### [H-35](report.md#h-35-permissionless-force-close-can-capture-the-partyb-liquidation-reward) — Permissionless force close can capture the PartyB liquidation reward

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Permissionless force-close paid the PartyB liquidation LF tip to `msg.sender`, letting a third party capture the reward. The tip now credits `quote.partyA`.

Evidence: `test/audit/H35.test.ts`.

### [H-38](report.md#h-38-zero-cva-liquidations-can-select-late-and-divide-by-zero) — Zero-CVA liquidations can select LATE and divide by zero

- **Severity:** High
- **Verdict:** `valid`
- **Disposition:** `fixed`

Zero-total-CVA liquidations could still select LATE settlement and divide by `totalCva`. LATE settlement now skips that division when total CVA is zero.

Evidence: `test/audit/H38.test.ts`.

### [M-02](report.md#m-02-same-timestamp-old-liquidation-prices-can-be-reused) — Same-timestamp old liquidation prices can be reused

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Symbol prices keyed only by timestamp could be reused across liquidation IDs in the same second. Prices are now bound to `keccak256(liquidationId)`; skipping `setSymbolsPrice` on the same timestamp no longer silently reuses another liquidation’s prices.

Evidence: `test/audit/M02.test.ts`.

### [M-03](report.md#m-03-liquidation-dispute-accumulator-ignores-cva-released-at-settlement) — Liquidation dispute accumulator ignores CVA released at settlement

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Dispute settlement’s positive-leg cap ignored CVA released at settlement, disagreeing with settle accounting. The cap now includes settlement CVA the same way settle does.

Evidence: `test/audit/M03.test.ts`.

### [M-10](report.md#m-10-suspension-does-not-block-several-user-state-changing-paths) — Suspension does not block several user state-changing paths

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Suspension blocked some paths but not deallocate / PartyA cancel-close flows. Those paths now require `notSuspended`.

Evidence: `test/audit/M10.test.ts`.

### [M-11](report.md#m-11-global-pause-does-not-stop-internal-transfers) — Global pause does not stop internal transfers

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

`whenNotInternalTransferPaused` ignored `globalPaused`, so global pause did not stop internal transfers. It now checks `globalPaused` as well.

Evidence: `test/audit/M11.test.ts`.

### [M-13](report.md#m-13-trusted-observer-rotation-does-not-re-encrypt-existing-observer-state) — Trusted observer rotation does not re-encrypt existing observer state

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Rotating the trusted observer did not re-encrypt existing observer ciphertext, leaving stale material for the old key. On rotation we switch the active observer address first, then an admin can batch-migrate historical observer ciphertext (`migrateObserverForPartyA` / `migrateObserverForPartyBs`).

Evidence: `test/audit/M13.test.ts`.

### [M-15](report.md#m-15-pricevalidtime-is-configured-but-not-enforced) — `priceValidTime` is configured but not enforced

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

`priceValidTime` was configured but freshness was not consistently enforced after Muon stopped carrying UPNL. Price freshness now keys off `priceValidTime` alone; `upnlValidTime` remains unused ABI/storage leftover.

Evidence: `test/audit/M15.test.ts`.

### [M-22](report.md#m-22-coti-dependencies-are-floating-git-branches) — COTI dependencies are floating Git branches

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

COTI packages were referenced via floating Git feature branches, so clean clones could drift. `package.json` now pins exact registry versions `@coti-io/coti-contracts@1.3.1` and `@coti-io/coti-ethers@1.0.6` (lockfile remains gitignored by repo policy).

Evidence: `test/audit/M22.test.ts`.

### [M-23](report.md#m-23-observer-events-are-missing-for-partial-fill-child-quotes) — Observer events are missing for partial-fill child quotes

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Partial-fill child quotes did not emit `ObserverSendQuote`, so observers missed child intent. Child open now emits `ObserverSendQuote` alongside the public send path.

Evidence: `test/audit/M23.test.ts`.

### [M-26](report.md#m-26-uint8-loop-counters-make-large-batches-revert) — `uint8` loop counters make large batches revert

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Several unbounded admin/batch loops used `uint8` counters and reverted above 255 items. Counters are `uint256`.

Evidence: `test/audit/M26.test.ts`.

### [M-34](report.md#m-34-balance-change-event-types-leak-private-pnl-direction) — Balance-change event types leak private PnL direction

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Settlement/liquidation balance events used a single direction type, leaking PnL sign. Those paths now dual-emit IN+OUT like close, matching the established pattern.

Evidence: `test/audit/M34.test.ts`.

### [M-37](report.md#m-37-liquidation-dispute-resolution-accepts-private-settlement-amounts-as-plaintext-calldata) — Liquidation dispute resolution accepts private settlement amounts as plaintext calldata

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

`resolveLiquidationDispute` took plaintext settlement amounts in calldata. It now takes `itInt256[]` and `validateCiphertext` before use.

Evidence: `test/audit/M37.test.ts`.

### [M-44](report.md#m-44-liquidation-cleanup-can-leave-observer-ciphertext-state-stale) — Liquidation cleanup can leave observer ciphertext state stale

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Liquidating pending PartyA positions could zero PartyB pending locks without writing the observer ciphertext copy, leaving stale observer state. Cleanup now goes through `storePartyBPendingLockedBalance`.

Evidence: `test/audit/M44.test.ts`.

### [M-47](report.md#m-47-plain-liquidation-detail-fields-stay-stale-after-encrypted-deficit-and-fee-writes) — Plain liquidation detail fields stay stale after encrypted deficit and fee writes

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

View liquidation detail still exposed stale unused plaintext fields after encrypted deficit/fee writes. `ViewLiquidationDetail` drops those fields so views match encrypted storage.

Evidence: `test/audit/M47.test.ts`.

### [M-50](report.md#m-50-dust-close-requests-can-lock-positions-until-partya-cancels-or-the-deadline-expires) — Dust close requests can lock positions until PartyA cancels or the deadline expires

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `fixed`

Dust close requests below the minimum proportional close could lock a position until cancel/deadline. `requireMinProportionalCloseAmount` now runs at close-request time.

Evidence: `test/audit/M50.test.ts`.

### [L-01](report.md#l-01-liquidation-fee-splits-silently-discard-rounding-remainders) — Liquidation-fee splits silently discard rounding remainders

- **Severity:** Low
- **Verdict:** `valid`
- **Disposition:** `fixed`

Liquidation fee splits discarded rounding dust. PartyA split assigns remainder to the second share; PartyB position-floor dust goes to the liquidator.

Evidence: `test/audit/L01.test.ts`.

### [L-06](report.md#l-06-partyb-filtered-position-views-scan-the-wrong-range-and-return-sparse-results) — PartyB-filtered position views scan the wrong range and return sparse results

- **Severity:** Low
- **Verdict:** `valid`
- **Disposition:** `fixed`

PartyB-filtered position views scanned the wrong range and returned sparse/padded results. Views are now compact and clamped to `lastId`.

Evidence: `test/audit/L06.test.ts`.

### [L-08](report.md#l-08-fee-distributor-can-retain-rounding-dust-while-reporting-the-full-amount-claimed) — Fee distributor can retain rounding dust while reporting the full amount claimed

- **Severity:** Low
- **Verdict:** `valid`
- **Disposition:** `fixed`

Fee distributor could retain floor dust while events reported the full claimed amount. The last stakeholder now receives the remainder.

Evidence: `test/audit/L08.test.ts`.

## Won't fix / design-choice

### [H-06](report.md#h-06-account-allocation-events-leak-private-balance-deltas) — Account allocation events leak private balance deltas

- **Severity:** High
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Allocate/deallocate (and related) events emit plaintext movement amounts while allocated storage is encrypted. Under **H-13**, free collateral is intentionally public until private tokens exist, so allocate size is already inferable from free-balance changes. We accept plaintext allocate events for now; revisit with private tokens.

Evidence: follows the H-13 design decision (no dedicated `H06` test).

### [H-07](report.md#h-07-reserve-vault-and-fee-collector-events-leak-private-accounting-amounts) — Reserve vault and fee collector events leak private accounting amounts

- **Severity:** High
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Reserve/fee collector events still publish plaintext movement amounts. Same H-13 boundary: free-balance and related public flows already reveal comparable deltas. Encrypting only these events without private free collateral would not close the privacy model.

Evidence: follows the H-13 design decision (no dedicated `H07` test).

### [H-13](report.md#h-13-deposited-free-collateral-and-bridge-amounts-remain-plaintext) — Deposited free collateral and bridge amounts remain plaintext

- **Severity:** High
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Deposited free collateral and bridge amounts remain plaintext by design for this release. Encrypting them without private tokens / private ERC-20 plumbing would be incomplete and break deposit UX. Related findings ([H-06](report.md#h-06-account-allocation-events-leak-private-balance-deltas), [H-27](report.md#h-27-account-balance-deltas-remain-public-calldata-despite-encrypted-storage), and [H-07](report.md#h-07-reserve-vault-and-fee-collector-events-leak-private-accounting-amounts)) accept the same public-delta boundary until a private-token migration.

Evidence: design decision (no dedicated `H13` test); see H-06 / H-27 entries.

### [H-27](report.md#h-27-account-balance-deltas-remain-public-calldata-despite-encrypted-storage) — Account balance deltas remain public calldata despite encrypted storage

- **Severity:** High
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Deposit/withdraw/bridge/allocate calldata still exposes movement amounts. Follows **H-13**: free/bridge ledgers are public until private tokens, so encrypting only calldata while storage/events stay public would not achieve meaningful privacy.

Evidence: follows the H-13 design decision (no dedicated `H27` test).

### [H-32](report.md#h-32-emergency-close-is-blocked-when-a-party-is-already-insolvent) — Emergency close is blocked when a party is already insolvent

- **Severity:** High
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Emergency close reverts when a party is already insolvent. That solvency gate is intentional: insolvent accounts should go through liquidation, which remains available under PartyB emergency controls. We are not removing the gate.

Evidence: `test/audit/H32.test.ts`.

### [M-14](report.md#m-14-observer-balance-change-events-are-missing-for-non-accounting-balance-mutations) — Observer balance-change events are missing for non-accounting balance mutations

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `wontfix`

`ObserverBalanceChange` is emitted on allocate/deallocate only; PnL/fee paths update observer storage without events. Accepted: observers should poll views for those updates (same approach as [M-40](report.md#m-40-trusted-observer-events-are-missing-for-position-execution)). Emitting on every private balance mutation would widen the public event surface.

Evidence: `test/audit/M14.test.ts`.

### [M-16](report.md#m-16-public-liquidation-type-leaks-the-private-deficit-range) — Public liquidation type leaks the private deficit range

- **Severity:** Medium
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Public `liquidationType` can hint deficit magnitude buckets. We keep it public on purpose: liquidation severity is an operational signal for liquidators/UI, not treated as a private risk field.

Evidence: `test/audit/M16.test.ts`.

### [M-24](report.md#m-24-emergency-close-emits-the-close-price-as-plaintext) — Emergency close emits the close price as plaintext

- **Severity:** Medium
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Emergency close emits plaintext `closedPrice`. That value is the public Muon price used for the close; ordinary fill/force paths remain encrypted. Encrypting only the emergency-close price would disagree with the “Muon prices are public” model.

Evidence: `test/audit/M24.test.ts`.

### [M-25](report.md#m-25-encrypted-balance-change-events-mix-deltas-and-balance-snapshots) — Encrypted balance-change events mix deltas and balance snapshots

- **Severity:** Medium
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Encrypted balance-change events mix snapshot and delta semantics behind one shape. Intentional: `_type` selects snapshot vs delta. Documented in NatSpec rather than splitting into multiple event families.

Evidence: `test/audit/M25.test.ts`.

### [M-40](report.md#m-40-trusted-observer-events-are-missing-for-position-execution) — Trusted observer events are missing for position execution

- **Severity:** Medium
- **Verdict:** `valid`
- **Disposition:** `wontfix`

No observer events for open/fill execution. Same choice as [M-14](report.md#m-14-observer-balance-change-events-are-missing-for-non-accounting-balance-mutations): trusted observers poll quote/position views rather than relying on a full mirror of public execution events.

Evidence: `test/audit/M40.test.ts`.

### [M-49](report.md#m-49-public-quote-metadata-leaks-private-trading-intent) — Public quote metadata leaks private trading intent

- **Severity:** Medium
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Public quote metadata (symbol, party lists, affiliate, etc.) can reveal intent. We encrypt sizes/prices/balances, and keep routing/intent metadata public for matching and operations.

Evidence: `test/audit/M49.test.ts`.

### [L-04](report.md#l-04-pagination-views-underflow-when-start-exceeds-the-list-length) — Pagination views underflow when `start` exceeds the list length

- **Severity:** Low
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

Pagination with `start` past the list length can panic `0x11`. Accepted fail-loud behavior rather than soft-empty pages; callers should clamp `start`.

Evidence: `test/audit/L04.test.ts`.

### [L-05](report.md#l-05-next-id-views-return-the-current-last-id-not-the-next-id) — Next-ID views return the current last ID, not the next ID

- **Severity:** Low
- **Verdict:** `design-choice`
- **Disposition:** `wontfix`

`getNext*` helpers return the last assigned id, not `lastId+1`. Existing callers already add one. We clarified NatSpec rather than changing the ABI semantics.

Evidence: `test/audit/L05.test.ts`.

## Invalid / superseded

### [H-05](report.md#h-05-partya-liquidation-exposes-plaintext-risk-snapshots) — PartyA liquidation exposes plaintext risk snapshots

- **Severity:** High
- **Verdict:** `invalid`
- **Disposition:** `wontfix`

The report claimed PartyA liquidation still stored plaintext UPNL / unrealized-loss snapshots. In current code those fields are already `utInt256` with `offBoardToUser`. Remaining unused plaintext fields on liquidation detail views are addressed under [M-47](report.md#m-47-plain-liquidation-detail-fields-stay-stale-after-encrypted-deficit-and-fee-writes), not as a separate H-05 plaintext ledger.

Evidence: `test/audit/H05.test.ts`.

### [M-36](report.md#m-36-deferred-liquidation-reimbursement-can-underflow-when-current-availability-exceeds-allocated-balance) — Deferred liquidation reimbursement can underflow when current availability exceeds allocated balance

- **Severity:** Medium
- **Verdict:** `invalid`
- **Disposition:** `wontfix`

Claimed deferred reimbursement could underflow when current availability exceeded allocated. After the [H-16](report.md#h-16-deferred-liquidation-type-uses-current-balance-instead-of-the-signed-snapshot) fix, insolvency and reimbursement share one snapshot available (a value cannot be both `< 0` and `> 0`), so the reported underflow path does not apply.

Evidence: `test/audit/M36.test.ts`.

### [L-03](report.md#l-03-editaccountname-lacks-account-ownership-validation) — `editAccountName` lacks account ownership validation

- **Severity:** Low
- **Verdict:** `invalid`
- **Disposition:** `wontfix`

Report suggested missing ownership checks on `editAccountName`. The function only writes `accounts[msg.sender]` (index into the caller’s list); a foreign address argument cannot rename another user’s account or move funds.

Evidence: `test/audit/L03.test.ts`.

### [L-09](report.md#l-09-multicall-result-arrays-are-returned-empty-for-successful-calls) — Multicall result arrays are returned empty for successful calls

- **Severity:** Low
- **Verdict:** `invalid`
- **Disposition:** `wontfix`

Claimed multicall returned empty arrays due to Solidity memory struct assignment. That assignment is a reference copy, not a wipe; `tryAggregate` / `aggregate3` return data is intact (false positive).

Evidence: `test/audit/L09.test.ts`.

## Evidence layout

Regression and static checks live under `test/audit/`. Prefer COTI testnet for end-to-end checks (`defaultNetwork` is `coti-testnet`).

Finding text and severity remain authoritative in [`report.md`](report.md).
