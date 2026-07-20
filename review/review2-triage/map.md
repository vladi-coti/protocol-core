# Wayfinder Map: Review2 Audit Triage

`wayfinder:map` — local markdown tracker for [`report.md`](../report.md) (50 findings).

## Destination

Every finding in review2 has a recorded **verdict** (valid / invalid / partial / design choice), **evidence** (testnet test or code proof), and **fix disposition** (implement / defer / wontfix / needs-human). After triage, P0 logic findings have agent-ready fix briefs and failing tests ready for `diagnosing-bugs` → `tdd` → `implement`.

## Notes

- **Domain:** COTI privacy fork of Symmio protocol-core (Solidity + Hardhat testnet).
- **Skills per session:** `diagnosing-bugs` (validate), `tdd` + `implement` (fix — only after validation ticket closes), `code-review` (post-fix).
- **Test policy:** COTI testnet by default; smallest meaningful `--grep` first.
- **Prior review context:** [`review/review1/issue-tracker.md`](../../review1/issue-tracker.md) — many related issues already fixed; review2 may overlap or supersede.
- **Ticket labels:** `wayfinder:research` (AFK validation), `wayfinder:grilling` (design choice), `group:logic-security`, `group:privacy-leak`, `group:design-product`.
- **One ticket per session.** Claim by editing ticket status to `in-progress`.
- **Ticket `status` (frontmatter):**
  | Value | Meaning |
  | --- | --- |
  | `open` | Not started / parked |
  | `in-progress` | Claimed this session (`wip` also ok) |
  | `closed` | Triage finished (`done` / `fixed` / `resolved` also ok — build maps them to closed) |

  Source of truth = `tickets/*.md` frontmatter; regenerate with `node review/review2-triage/build-progress.mjs`. When closing: append one line under **Decisions so far**, remove from **Frontier**.

## Group 1 — Logic / Security Exploit (27 tickets)

Fund loss, stuck state, wrong accounting, auth bypass, DoS, or incorrect lifecycle. **Fix if valid.**

| Pri | Ticket | Finding | Blocks |
| --- | --- | --- | --- |
| P0 | [Validate C-01 unsigned→signed cast](tickets/logic-P0-C-01.md) | C-01 | — |
| P0 | [Validate H-02 unchecked signed MPC math](tickets/logic-P0-H-02.md) | H-02 | — |
| P0 | [Validate H-38 zero-CVA LATE divide-by-zero](tickets/logic-P0-H-38.md) | H-38 | — |
| P0 | [Validate H-12 settleAndForceClose wrong PartyA](tickets/logic-P0-H-12.md) | H-12 | — |
| P0 | [Validate H-14 force-close stale PartyB deficit](tickets/logic-P0-H-14.md) | H-14 | — |
| P0 | [Validate H-15 PartyB liquidation LF revert](tickets/logic-P0-H-15.md) | H-15 | — |
| P0 | [Validate H-16 deferred liquidation snapshot drift](tickets/logic-P0-H-16.md) | H-16 | — |
| P0 | [Validate H-26 force-close pre-close liquidation mismatch](tickets/logic-P0-H-26.md) | H-26 | — |
| P1 | [Validate H-32 emergency close blocked when insolvent](tickets/logic-P1-H-32.md) | H-32 | — |
| P1 | [Validate H-33 fee distributor encrypted accrual mismatch](tickets/logic-P1-H-33.md) | H-33 | — |
| P1 | [Validate H-34 expired close request force-closeable](tickets/logic-P1-H-34.md) | H-34 | — |
| P1 | [Validate H-35 permissionless liquidation reward capture](tickets/logic-P1-H-35.md) | H-35 | — |
| P2 | [Validate M-02 stale liquidation price reuse](tickets/logic-P2-M-02.md) | M-02 | — |
| P2 | [Validate M-03 dispute accumulator ignores CVA](tickets/logic-P2-M-03.md) | M-03 | — |
| P2 | [Validate M-10 suspension gaps](tickets/logic-P2-M-10.md) | M-10 | — |
| P2 | [Validate M-11 global pause skips internal transfer](tickets/logic-P2-M-11.md) | M-11 | — |
| P2 | [Validate M-15 priceValidTime not enforced](tickets/logic-P2-M-15.md) | M-15 | — |
| P2 | [Validate M-26 uint8 batch loop overflow](tickets/logic-P2-M-26.md) | M-26 | — |
| P2 | [Validate M-36 deferred liquidation reimbursement underflow](tickets/logic-P2-M-36.md) | M-36 | — |
| P2 | [Validate M-50 dust close request locks position](tickets/logic-P2-M-50.md) | M-50 | — |
| P3 | [Validate L-01 liquidation fee rounding dust](tickets/logic-P3-L-01.md) | L-01 | — |
| P3 | [Validate L-03 editAccountName ownership](tickets/logic-P3-L-03.md) | L-03 | — |
| P3 | [Validate L-04 pagination underflow](tickets/logic-P3-L-04.md) | L-04 | — |
| P3 | [Validate L-05 next-ID view off-by-one](tickets/logic-P3-L-05.md) | L-05 | — |
| P3 | [Validate L-06 PartyB position view sparse scan](tickets/logic-P3-L-06.md) | L-06 | — |
| P3 | [Validate L-08 fee distributor rounding event mismatch](tickets/logic-P3-L-08.md) | L-08 | — |
| P3 | [Validate L-09 multicall empty return data](tickets/logic-P3-L-09.md) | L-09 | — |

## Group 2 — Privacy Leak (20 tickets)

Calldata, events, views, revert oracles, or metadata disclosure. **Fix or explicitly accept as public.**

| Pri | Ticket | Finding | Blocks |
| --- | --- | --- | --- |
| P0 | [Validate H-04 force-close price oracle](tickets/privacy-P0-H-04.md) | H-04 | — |
| P0 | [Validate H-08 balance threshold revert oracle](tickets/privacy-P0-H-08.md) | H-08 | — |
| P1 | [Validate H-01 Muon UPNL plaintext calldata](tickets/privacy-P1-H-01.md) | H-01 | grilling — preferred **C**: Muon prices only + on-chain UPNL¹ |
| P1 | [Validate H-06 allocation event plaintext deltas](tickets/privacy-P1-H-06.md) | H-06 | [Decide account delta privacy model](tickets/design-H-13-free-collateral-privacy.md)¹ |
| P1 | [Validate H-07 reserve/fee event plaintext](tickets/privacy-P1-H-07.md) | H-07 | — |
| P1 | [Validate H-11 settlement event plaintext opened prices](tickets/privacy-P1-H-11.md) | H-11 | — |
| P1 | [Validate H-27 account movement plaintext calldata](tickets/privacy-P1-H-27.md) | H-27 | [Decide account delta privacy model](tickets/design-H-13-free-collateral-privacy.md) |
| P2 | [Validate H-05 PartyA liquidation plaintext snapshots](tickets/privacy-P2-H-05.md) | H-05 | — |
| P2 | [Validate H-28 quote views expose system ciphertext](tickets/privacy-P2-H-28.md) | H-28 | — |
| P2 | [Validate M-37 dispute settlement plaintext calldata](tickets/privacy-P2-M-37.md) | M-37 | — |
| P2 | [Validate M-24 emergency close plaintext price event](tickets/privacy-P2-M-24.md) | M-24 | — |
| P3 | [Validate M-14 missing observer balance events](tickets/privacy-P3-M-14.md) | M-14 | [Decide observer rotation model](tickets/design-M-13-observer-rotation.md) |
| P3 | [Validate M-16 liquidation type range leak](tickets/privacy-P3-M-16.md) | M-16 | [Decide liquidation type disclosure](tickets/design-M-16-liquidation-type-disclosure.md) |
| P3 | [Validate M-23 missing partial-fill observer events](tickets/privacy-P3-M-23.md) | M-23 | — |
| P3 | [Validate M-25 balance event delta vs snapshot semantics](tickets/privacy-P3-M-25.md) | M-25 | — |
| P3 | [Validate M-34 PnL direction via event type](tickets/privacy-P3-M-34.md) | M-34 | — |
| P3 | [Validate M-40 missing observer execution events](tickets/privacy-P3-M-40.md) | M-40 | — |
| P3 | [Validate M-44 stale observer ciphertext after cleanup](tickets/privacy-P3-M-44.md) | M-44 | — |
| P3 | [Validate M-47 stale plaintext liquidation detail fields](tickets/privacy-P3-M-47.md) | M-47 | — |
| P3 | [Validate M-49 public quote metadata intent leak](tickets/privacy-P3-M-49.md) | M-49 | [Decide quote metadata privacy scope](tickets/design-M-49-quote-metadata-privacy.md) |

¹ H-01 grilling: prefer **C** — Muon prices only (no encrypt/decrypt); UPNL on-chain in MPC. Do not grant Muon nodes observer/proxy decrypt.

## Group 3 — Design / Product Decision (5 tickets)

Architectural or intentional tradeoffs. **Decide before implementing related privacy fixes.**

| Pri | Ticket | Finding | Blocks |
| --- | --- | --- | --- |
| P0 | [Decide free collateral privacy model](tickets/design-H-13-free-collateral-privacy.md) | H-13 | H-27, H-06 fix approach |
| P1 | [Decide observer rotation model](tickets/design-M-13-observer-rotation.md) | M-13 | M-14, M-44 fix approach |
| P1 | [Decide COTI dependency pinning policy](tickets/design-M-22-coti-dependencies.md) | M-22 | — |
| P2 | [Decide liquidation type disclosure](tickets/design-M-16-liquidation-type-disclosure.md) | M-16 | M-16 privacy fix |
| P2 | [Decide quote metadata privacy scope](tickets/design-M-49-quote-metadata-privacy.md) | M-49 | M-49 privacy fix |

## Frontier (start here)

Unblocked, highest priority — pick **one** per session:

*(empty — logic/privacy P3 validation queue clear; design-blocked / parked remain below)*

Parked (not frontier): [M-22 COTI deps](tickets/design-M-22-coti-dependencies.md) — wait until signed forks merge to main, then pin.
Blocked on design: M-16 (← design-M-16), M-49 (← design-M-49).

## Early privacy / architecture decisions (grill soon)

| Decision ticket | Gates |
| --- | --- |
| [H-01 Muon UPNL model](tickets/privacy-P1-H-01.md) | almost all Muon-backed APIs; H-05, M-47, settlement/force UPNL surfaces — **closed (path C)** |
| [H-13 free collateral / deltas](tickets/design-H-13-free-collateral-privacy.md) | H-06, H-27 — **closed (intentionally public until private tokens)** |
| [M-13 observer rotation](tickets/design-M-13-observer-rotation.md) | M-14, M-44; proxy + graph — **closed (flip-first + admin batched migrate landed)** |
| [M-49 quote metadata](tickets/design-M-49-quote-metadata-privacy.md) | M-49 |
| [M-16 liquidation type](tickets/design-M-16-liquidation-type-disclosure.md) | M-16 privacy |
| [M-22 COTI dep pins](tickets/design-M-22-coti-dependencies.md) | all client builds / mainnet repro — **policy: defer pin until signed forks merge to main; ticket open** |

## Decisions so far

- [Validate C-01 unsigned→signed cast](tickets/logic-P0-C-01.md) — **hardened**; `toNonNegativeSigned` at cited sites + remaining `.toSigned()` swept (`LibQuote`/`LibSettlement`/funding/force/liquidation); static tripwire in `test/audit/C01.test.ts`; sim green.
- [Validate H-02 unchecked signed MPC math](tickets/logic-P0-H-02.md) — **valid**; `gtInt256.checkedAdd/checkedSub` repo-wide (only locked-value struct helpers remain); static tripwire in `test/audit/H02.test.ts`; sim green.
- [Validate H-38 zero-CVA LATE divide-by-zero](tickets/logic-P0-H-38.md) — **valid**; LATE settlement skips `/ totalCva` when total CVA is 0; `test/audit/H38.test.ts` green on testnet.
- [Validate H-12 settleAndForceClose wrong PartyA](tickets/logic-P0-H-12.md) — **valid**; settle against `quote.partyA` not `msg.sender`; `test/audit/H12.test.ts` green on sim (+ testnet trust sample).
- [Validate H-14 force-close stale PartyB deficit](tickets/logic-P0-H-14.md) — **valid**; liquidate with post-reserve `gtWithReserve`; `test/audit/H14.test.ts` green on sim.
- [Validate H-15 PartyB liquidation LF revert](tickets/logic-P0-H-15.md) — **valid**; cap `remainingLf` to PartyB allocated before `checkedSub`; `test/audit/H15.test.ts` green on sim + testnet.
- [Validate H-16 deferred liquidation snapshot drift](tickets/logic-P0-H-16.md) — **valid**; deferred type/reimbursement use signed allocated snapshot; `test/audit/H16.test.ts` green on sim + testnet.
- [Validate H-26 force-close pre-close liquidation mismatch](tickets/logic-P0-H-26.md) — **valid**; unlock closed-quote cva+lf on PartyB locks before `liquidatePartyBFromAvailable`; `test/audit/H26.test.ts` green on sim (H-14 still green).
- [Validate H-04 force-close price oracle](tickets/privacy-P0-H-04.md) — **valid**; Muon verify before private close-price onboard/decrypt; `test/audit/H04.test.ts` green on sim.
- [Validate H-08 balance threshold revert oracle](tickets/privacy-P0-H-08.md) — **valid**; public free-balance check before allocated-limit decrypt in allocate/internalTransfer; `test/audit/H08.test.ts` green on sim.
- [Validate H-32 emergency close blocked when insolvent](tickets/logic-P1-H-32.md) — **design-choice / wontfix**; solvency gate intentional; liquidation still works under PartyB emergency; `test/audit/H32.test.ts` dual PASS.
- [Validate H-33 fee distributor encrypted accrual mismatch](tickets/logic-P1-H-33.md) — **valid**; `claimAllFeeCollectorBalance` + distributor claims before withdraw; `test/audit/H33.test.ts` dual PASS.
- [Validate H-34 expired close request force-closeable](tickets/logic-P1-H-34.md) — **valid**; require `block.timestamp <= quote.deadline` on force close; `test/audit/H34.test.ts` dual PASS.
- [Validate H-35 permissionless liquidation reward capture](tickets/logic-P1-H-35.md) — **valid**; force-close liq tip → `quote.partyA` not `msg.sender`; `test/audit/H35.test.ts` dual PASS.
- [Decide free collateral privacy model](tickets/design-H-13-free-collateral-privacy.md) — **design-choice / wontfix**; free/bridge remain public until private tokens; H-06/H-27 follow.
- [Validate H-06 allocation event plaintext deltas](tickets/privacy-P1-H-06.md) — **design-choice / wontfix**; follows H-13 (public free balance already reveals allocate size).
- [Validate H-27 account movement plaintext calldata](tickets/privacy-P1-H-27.md) — **design-choice / wontfix**; follows H-13.
- [Validate H-07 reserve/fee event plaintext amounts](tickets/privacy-P1-H-07.md) — **design-choice / wontfix**; free-balance deltas already reveal movements under H-13.
- [Validate H-11 settlement event plaintext opened prices](tickets/privacy-P1-H-11.md) — **valid**; strip `updatedPrices` from `SettleUpnl`; `test/audit/H11.test.ts` green on sim.
- [Validate M-14 missing observer balance events](tickets/privacy-P3-M-14.md) — **valid / wontfix**; ObserverBalanceChange only on allocate/deallocate; PnL/fee paths update observer storage but skip events — require view polling (aligns M-13). `test/audit/M14.test.ts` sim green.
- [Validate M-44 stale observer ciphertext after cleanup](tickets/privacy-P3-M-44.md) — **valid / implement (done)**; `liquidatePendingPositionsPartyA` now uses `storePartyBPendingLockedBalance`. `test/audit/M44.test.ts` sim green.
- [Decide/implement observer rotation model](tickets/design-M-13-observer-rotation.md) — **valid / implement (done)**; flip-first + `migrateObserverForPartyA` / `migrateObserverForPartyBs` admin catch-up. `test/audit/M13.test.ts` sim green.
- [Validate M-02 stale liquidation price reuse](tickets/logic-P2-M-02.md) — **valid / implement (done)**; bind `symbolsPrices` to `keccak256(liquidationId)`; same-timestamp skip-`setSymbolsPrice` now reverts. `test/audit/M02.test.ts` sim green.
- [Validate H-05 PartyA liquidation plaintext snapshots](tickets/privacy-P2-H-05.md) — **invalid / wontfix**; `upnl`/`totalUnrealizedLoss` already `utInt256` + `offBoardToUser`; husks → M-47. `test/audit/H05.test.ts` sim green.
- [Validate M-03 dispute accumulator ignores CVA](tickets/logic-P2-M-03.md) — **valid / implement (done)**; positive-leg cap uses `allocated+settlementCva` like settle. `test/audit/M03.test.ts` sim green.
- [Validate M-10 suspension gaps](tickets/logic-P2-M-10.md) — **valid / implement (done)**; `notSuspended` on deallocate + PartyA cancel/close paths. `test/audit/M10.test.ts` sim green.
- [Validate M-11 global pause skips internal transfer](tickets/logic-P2-M-11.md) — **valid / implement (done)**; `whenNotInternalTransferPaused` now checks `globalPaused`. `test/audit/M11.test.ts` sim green.
- [Validate M-15 priceValidTime not enforced](tickets/logic-P2-M-15.md) — **valid / implement (done)**; sole freshness knob `priceValidTime` (H-01 path C); `upnlValidTime` ABI/storage husk. `test/audit/M15.test.ts` sim green.
- [Validate M-26 uint8 batch loop overflow](tickets/logic-P2-M-26.md) — **valid / implement (done)**; unbounded batch `for (uint8)` → `uint256`; `addSymbols(256)` green. `test/audit/M26.test.ts` sim green.
- [Validate M-36 deferred liquidation reimbursement underflow](tickets/logic-P2-M-36.md) — **invalid / wontfix**; H-16 made insolvency + reimbursement share one snapshot available (`lt(0)` then `gt(0)` dead). `test/audit/M36.test.ts` sim green.
- [Validate M-50 dust close request locks position](tickets/logic-P2-M-50.md) — **valid / implement (done)**; `requireMinProportionalCloseAmount` at close-request time. `test/audit/M50.test.ts` sim green.
- [Validate L-01 liquidation fee rounding dust](tickets/logic-P3-L-01.md) — **valid / implement (done)**; PartyA `lf2=lf-lf1`; PartyB position-floor dust → liquidator. `test/audit/L01.test.ts` dual PASS.
- [Validate H-28 quote views expose system ciphertext](tickets/privacy-P2-H-28.md) — **valid / implement (done)**; public views return `ViewQuote` (`ctUint256` only), not storage `Quote`/`utUint256`. `test/audit/H28.test.ts` dual PASS.
- [Validate M-37 dispute settlement plaintext calldata](tickets/privacy-P2-M-37.md) — **valid / implement (done)**; `resolveLiquidationDispute` takes `itInt256[]` + `validateCiphertext`. `test/audit/M37.test.ts` dual PASS.
- [Validate M-24 emergency close plaintext price event](tickets/privacy-P2-M-24.md) — **design-choice / wontfix**; closedPrice = public Muon `upnlSig.price` (H-01 path C); fill/force stay encrypted. `test/audit/M24.test.ts` dual PASS.
- [Validate L-03 editAccountName ownership](tickets/logic-P3-L-03.md) — **invalid / wontfix**; only mutates `accounts[msg.sender]`; no victim storage/funds impact. `test/audit/L03.test.ts`.
- [Validate L-04 pagination underflow](tickets/logic-P3-L-04.md) — **design-choice / wontfix**; out-of-range `start` may panic `0x11` (fail loud). `test/audit/L04.test.ts`.
- [Validate M-23 missing partial-fill observer events](tickets/privacy-P3-M-23.md) — **valid / implement (done)**; emit `ObserverSendQuote` on partial-fill child. `test/audit/M23.test.ts`.
- [Validate L-05 next-ID view off-by-one](tickets/logic-P3-L-05.md) — **design-choice / wontfix**; `getNext*` returns last assigned `lastId` (callers already `+1`). NatSpec clarified. `test/audit/L05.test.ts`.

## Not yet specified

- **Implement-fix tickets** — one per validated finding; created when validation closes with verdict `valid` or `partial`. Skills: `tdd` → `implement`.
- **Cross-finding dedup** — C-01 / H-02 hardening landed together (checked signed ops + guarded unsigned→signed casts); no separate implement tickets needed.
- **Review1 overlap** — several review2 findings may already be partially addressed (e.g. H-05 vs report5#3, H-16 vs report1#4). Validation tickets must check current code, not assume greenfield.
## Out of scope

- Giving Muon network participants observer/proxy decrypt (rejected under H-01 preferred path).
- Private free-collateral / bridge / allocate amounts without private tokens (accepted public under [H-13](tickets/design-H-13-free-collateral-privacy.md); revisit later).
