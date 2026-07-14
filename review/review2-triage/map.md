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
| P1 | [Validate H-01 Muon UPNL plaintext calldata](tickets/privacy-P1-H-01.md) | H-01 | — (fix likely needs-human / Muon off-chain)¹ |
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

¹ H-01 fix path depends on Muon redesign — use design ticket for disposition even if leak is confirmed valid.

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

1. [Validate H-38 zero-CVA LATE divide-by-zero](tickets/logic-P0-H-38.md)
2. [Validate H-12 settleAndForceClose wrong PartyA](tickets/logic-P0-H-12.md)
3. [Decide free collateral privacy model](tickets/design-H-13-free-collateral-privacy.md) *(parallel track)*

## Decisions so far

- [Validate C-01 unsigned→signed cast](tickets/logic-P0-C-01.md) — **partial/valid**; sendQuote high-bit bypass not reproduced; added `LibEncryption.toNonNegativeSigned` + `test/audit/C01.test.ts` at cited sites.
- [Validate H-02 unchecked signed MPC math](tickets/logic-P0-H-02.md) — **valid**; `gtInt256.checkedAdd/checkedSub` at cited LibAccount/LibSettlement/LibQuote/LibSolvency paths (+ follow-up sweep of remaining signed add/sub); `test/audit/H02.test.ts` passed on testnet.

## Not yet specified

- **Implement-fix tickets** — one per validated finding; created when validation closes with verdict `valid` or `partial`. Skills: `tdd` → `implement`.
- **Cross-finding dedup** — C-01 and H-02 may share a single bounds-checking fix; decide during P0 validation whether to merge implementation tickets.
- **Review1 overlap** — several review2 findings may already be partially addressed (e.g. H-05 vs report5#3, H-16 vs report1#4). Validation tickets must check current code, not assume greenfield.
- **Muon architecture ticket** — if H-01 is confirmed, may need a separate grilling session on off-chain Muon changes (out of repo scope).

## Out of scope

- Rewriting Muon off-chain signer infrastructure (on-chain validation only; disposition documented in H-01 ticket).
- Full encrypted calldata for every account movement without product sign-off (gated by [Decide free collateral privacy model](tickets/design-H-13-free-collateral-privacy.md)).
