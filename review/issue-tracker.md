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
| 23 | [`report3#11`](report3.md#L185-L192) | open | Wrong `quoteId` / missing open-position event in `lockAndOpenQuote` |
| 24 | [`report4#1`](report4.md#L1-L11) | fixed | PartyA liquidation cannot terminate because settlement path is dead |
| 25 | [`report4#2`](report4.md#L12-L50) | open | Revert oracle over encrypted thresholds |
| 26 | [`report4#3`](report4.md#L51-L64) | open | Full-close / partial-close signal leaked via decrypt/branching |
| 27 | [`report4#4`](report4.md#L65-L67) | open | `setEncryptionAddress` skips partyB-side re-encryption |
| 28 | [`report4#5`](report4.md#L68-L70) | open | `internalTransfer` does not initialize recipient encrypted state |
| 29 | [`report4#6`](report4.md#L71-L79) | open | Trusted-mode early return strands key rotation |
| 30 | [`report4#7`](report4.md#L80-L95) | open | Misleading `mux` wrapper semantics |
| 31 | [`report4#8`](report4.md#L96-L106) | open | `initializePartyB` couples independent slots under one gate |
| 32 | [`report4#9`](report4.md#L107-L117) | open | `LibMuon.getChainId()` development FIXME |
| 33 | [`report4#10`](report4.md#L118-L120) | open | Read API changed to ciphertext return types |
| 34 | [`report4#11`](report4.md#L121-L124) | open | `setEncryptionAddress` missing guards and has fragile write ordering |
| 35 | [`report5#1`](report5.md#L1-L10) | partial | `forceClosePosition` decrypts negative available balance |
| 36 | [`report5#2`](report5.md#L11-L19) | open | `forceClosePosition` decrypts `quantityToClose` and `closePrice` |
| 37 | [`report5#3`](report5.md#L20-L35) | partial | Liquidation flows decrypt full financial state |
| 38 | [`report5#4`](report5.md#L36-L40) | open | `settlementStates` offboarded to partyA key only |
| 39 | [`report5#5`](report5.md#L41-L48) | open | Generic validation error regresses UX/debuggability |
| 40 | [`report5#6`](report5.md#L49-L59) | open | `mux` computes underflowing unselected arm |
| 41 | [`report5#7`](report5.md#L60-L73) | open | Event ABI/topic changes break integrations |
| 42 | [`report5#8`](report5.md#L74-L75) | open | `setEncryptionAddress` missing from interface |

## Coverage Check

- Total original findings across the five reports: `42`
- Total tracked findings in this file: `42`
