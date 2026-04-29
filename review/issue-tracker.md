# Issue Tracker

Tracker for the original findings from `review/report1.md` through `review/report5.md`.

Statuses are inherited from the prior deduped tracker, so duplicate findings across reports share the same status.

## Report Issues

| # | Finding | Status | Summary |
| --- | --- | --- | --- |
| 1 | [`report1#1`](report1.md#L1-L10) | fixed | Solvency branch math swapped |
| 2 | [`report1#2`](report1.md#L11-L14) | deferred | Muon verification and expiry checks disabled |
| 3 | [`report1#3`](report1.md#L15-L18) | fixed | No-op live selectors |
| 4 | [`report1#4`](report1.md#L19-L26) | fixed | Deferred liquidation snapshot bug |
| 5 | [`report2#1`](report2.md#L1-L3) | fixed | `lockAndOpenQuote` emits wrong-key event for partyA |
| 6 | [`report2#2`](report2.md#L4-L6) | fixed | Settlement event amount encrypted to wrong party key |
| 7 | [`report2#3`](report2.md#L7-L9) | fixed | Settlement decrypts `openedPrice` and `quoteOpenAmount` |
| 8 | [`report2#4`](report2.md#L10-L12) | fixed | `lockAndOpenQuote` takes plaintext fill/open params |
| 9 | [`report2#5`](report2.md#L13-L16) | fixed | Subaccount created without usable encryption address |
| 10 | [`report2#6`](report2.md#L17-L20) | fixed | `settleUpnl` / `forceClosePosition` leak balances via decrypt-and-emit |
| 11 | [`report2#7`](report2.md#L21-L28) | fixed | Trading-fee decrypt leaks `quantity * price` |
| 12 | [`report2#8`](report2.md#L29-L36) | fixed | Decrypted profitability comparison leaks PnL direction |
| 13 | [`report3#1`](report3.md#L1-L17) | fixed | Self-transfer allocation inflation bug |
| 14 | [`report3#2`](report3.md#L18-L48) | fixed | Class-level unchecked arithmetic problem |
| 15 | [`report3#3`](report3.md#L49-L61) | fixed | `settleUpnl` underflow wraps balances |
| 16 | [`report3#4`](report3.md#L62-L78) | fixed | `liquidatePartyB` underflow wraps value |
| 17 | [`report3#5`](report3.md#L79-L93) | fixed | `sendQuote` balance-check bypass after wrap/reinterpret |
| 18 | [`report3#6`](report3.md#L94-L115) | fixed | `trustedEncryptionAddress` privacy and migration failure |
| 19 | [`report3#7`](report3.md#L116-L136) | fixed | Full-balance decrypts in normal user flows |
| 20 | [`report3#8`](report3.md#L137-L151) | fixed | Corrupted identity fields in `SendQuote*` events |
| 21 | [`report3#9`](report3.md#L152-L168) | fixed | Liquidation decrypts settlement amount and partyB balance |
| 22 | [`report3#10`](report3.md#L169-L184) | fixed | Raw onboarding of uninitialized settlement ciphertext |
| 23 | [`report3#11`](report3.md#L185-L192) | fixed | Wrong `quoteId` / missing open-position event in `lockAndOpenQuote` |
| 24 | [`report4#1`](report4.md#L1-L11) | fixed | PartyA liquidation cannot terminate because settlement path is dead |
| 25 | [`report4#2`](report4.md#L12-L50) | deferred | Solver-side threshold oracle accepted under RFQ privacy model |
| 26 | [`report4#3`](report4.md#L51-L64) | partial | Avoidable full/partial close branch leaks removed; final lifecycle state remains public |
| 27 | [`report4#4`](report4.md#L65-L67) | fixed | `setEncryptionAddress` re-encrypts tracked partyB-side balances |
| 28 | [`report4#5`](report4.md#L68-L70) | fixed | `internalTransfer` initializes recipient encrypted state |
| 29 | [`report4#6`](report4.md#L71-L79) | fixed | Observer mode does not strand user key rotation |
| 30 | [`report4#7`](report4.md#L80-L95) | fixed | Removed unused misleading `LockedValuesOps.mux` wrapper |
| 31 | [`report4#8`](report4.md#L96-L106) | fixed | `initializePartyB` initializes PartyB-side slots independently |
| 32 | [`report4#9`](report4.md#L107-L117) | fixed | Removed stale `LibMuon.getChainId()` development FIXME |
| 33 | [`report4#10`](report4.md#L118-L120) | fixed | Ciphertext read API migration documented |
| 34 | [`report4#11`](report4.md#L121-L124) | fixed | `setEncryptionAddress` guards account state and writes mapping last |
| 35 | [`report5#1`](report5.md#L1-L10) | partial | `forceClosePosition` decrypts negative available balance |
| 36 | [`report5#2`](report5.md#L11-L19) | open | `forceClosePosition` decrypts `quantityToClose` and `closePrice` |
| 37 | [`report5#3`](report5.md#L20-L35) | partial | Liquidation flows decrypt full financial state |
| 38 | [`report5#4`](report5.md#L36-L40) | open | `settlementStates` offboarded to partyA key only |
| 39 | [`report5#5`](report5.md#L41-L48) | open | Generic validation error regresses UX/debuggability |
| 40 | [`report5#6`](report5.md#L49-L59) | open | `mux` computes underflowing unselected arm |
| 41 | [`report5#7`](report5.md#L60-L73) | open | Event ABI/topic changes break integrations |
| 42 | [`report5#8`](report5.md#L74-L75) | open | `setEncryptionAddress` missing from interface |

## Coverage Check

### Issue 25 Note

Issue 25 assumes partyB/solver must not learn partyA requested price or quantity before filling. The current RFQ model intentionally discloses those terms to the selected partyB via partyB-encrypted quote and close events, so the solver-side revert oracle does not add a new leak to that selected solver. This is accepted for selected solvers. The remaining security boundary is that non-selected partyBs and public observers must not be able to probe or decrypt those values; `openPosition` and `fillCloseRequest` are guarded by `onlyPartyBOfQuote`, and `lockQuote` only assigns `quote.partyB` after whitelist validation.

### Issue 26 Note

Issue 26 has two parts. The fix removes avoidable decrypted equality branches and branch-dependent gas differences from close request/fill validation. It does not hide final lifecycle state: after execution, whether a quote is `CLOSED` or remains `OPENED` is public protocol state. Fully hiding full-close versus partial-close would require redesigning quote status, position indexes, views, and events.

### Issue 27 Note

PartyB key rotation now tracks PartyB-to-PartyA relationships and re-encrypts PartyB allocated, locked, and pending locked balances for every tracked PartyA. Settlement state remains encrypted to PartyA plus the trusted observer copy; it is not PartyB self-decryption state.

### Issue 28 Note

`internalTransfer` now initializes the recipient as PartyA before crediting encrypted allocation. This writes encrypted zero `allocatedBalances`, `lockedBalances`, and `pendingLockedBalances` for fresh recipients, so later PartyA solvency and deallocation paths can safely onboard those slots.

### Issue 29 Note

The old trusted user-encryption mode no longer exists: `trustedEncryptionAddress` and the early return in `setEncryptionAddress` were removed by the observer refactor. Current `trustedObserverAddress` only controls separate observer ciphertexts through `offBoardToObserver`; it does not affect `getUserEncryptionAddress` or user-owned ciphertexts. A regression covers key rotation while observer mode is enabled, then disables observer mode and verifies the rotated user ciphertext still decrypts with the new user key.

### Issue 30 Note

`LockedValuesOps.mux` was unused and has been removed instead of documenting a misleading wrapper around COTI's reversed `MpcCore.mux(condition, a, b)` convention. Existing direct `MpcCore.mux` call sites are unchanged; the separate eager-evaluation/underflow concern remains tracked under Issue 40.

### Issue 31 Note

`initializePartyB` now checks PartyB locked balances, pending locked balances, settlement state, and allocated balance independently. The PartyB quote lock path delegates to the shared initializer, so a drifted zero slot can be repaired without wiping already-initialized sibling slots.

### Issue 32 Note

`LibMuon.getChainId()` now only returns `block.chainid`; the stale commented hardcoded fallback was removed.

### Issue 33 Note

The read API change is intentional for the privacy fork: sensitive `ViewFacet` reads return ciphertext and must be decrypted client-side by the owning user or configured observer. `PRIVACY_CHANGES.md` now documents affected read APIs, observer alternatives, and the fact that plaintext compatibility views are intentionally not provided.

### Issue 34 Note

`setEncryptionAddress` now uses the same pause, suspension, and PartyA liquidation guards as account mutations. PartyB key rotation also checks each tracked PartyA pair against `partyBLiquidationStatus` before re-encrypting PartyB-side balances. The `userEncryptionAddress` mapping write was moved after all re-encryption work succeeds; revert rollback already protected atomicity, but the new order removes the audit footgun.

- Total original findings across the five reports: `42`
- Total tracked findings in this file: `42`
