# Security Findings

### C-01: Unsigned encrypted values can become negative in signed solvency math

- Severity: Critical
- Summary: Encrypted unsigned values are cast into signed accounting math without proving they are within the signed integer range.
- Description: The protocol accepts several encrypted quote and balance values as unsigned quantities, but later reuses those values in signed margin, available-balance, and solvency formulas. The relevant paths do not prove that the encrypted unsigned value is less than `2^255` before it is interpreted as a signed encrypted value. In two's-complement signed arithmetic, values above that boundary are negative, so an oversized encrypted unsigned input can cross a trust boundary and become a negative accounting value instead of being rejected.

  This is especially dangerous because the affected values participate in quote validation, account balance availability, locked-balance accounting, and solvency checks. A protocol invariant should guarantee that any value entering signed encrypted math is representable as a non-negative signed value, but the current code relies on implicit assumptions rather than enforcing the range. Code references: `contracts/facets/PartyA/PartyAFacetImpl.sol:92`, `contracts/facets/PartyA/PartyAFacetImpl.sol:96`, `contracts/libraries/LibAccount.sol:62`, `contracts/libraries/LibAccount.sol:68`, `contracts/libraries/LibSolvency.sol:129`, `contracts/libraries/LibSolvency.sol:132`.
- Impact: An out-of-range encrypted value can be interpreted as negative, which can invert margin, solvency, settlement, or liquidation calculations instead of reverting.
- Attack path: A PartyA submits encrypted quote values near or above the signed boundary; later accounting casts those values to signed form and treats them as negative.
- Recommendation: Enforce signed-range bounds before every unsigned-to-signed encrypted conversion, or use distinct signed encrypted inputs with explicit validation.

### H-01: Muon UPNL signatures expose private PnL as plaintext calldata

- Severity: High
- Summary: Private PnL and risk values are transported in public Muon calldata.
- Description: The COTI fork encrypts many on-chain balances, but the Muon verification interface still exposes major risk values as ordinary public integers. UPNL, total unrealized loss, and deferred liquidation allocated balance are part of the calldata structs and are also included directly in the Muon signed hash payload. This means the values are disclosed at the contract ABI layer before any encrypted storage or encrypted event design can help.

  These fields are not isolated to one administrative action. They are consumed by deallocation, settlement, PartyB risk checks, force close, funding, and liquidation flows, so the public Muon ABI becomes a broad privacy bypass for the same risk data the COTI fork otherwise appears to protect. Code references: `contracts/storages/MuonStorage.sol:20`, `contracts/storages/MuonStorage.sol:23`, `contracts/libraries/muon/LibMuonAccount.sol:24`, `contracts/libraries/muon/LibMuonPartyB.sol:24`, `contracts/libraries/muon/LibMuonPartyB.sol:25`, `contracts/libraries/muon/LibMuonSettlement.sol:37`.
- Impact: PartyA and PartyB PnL snapshots are exposed during deallocation, settlement, funding, force-close, and liquidation flows.
- Attack path: Any observer reads the transaction calldata for Muon-backed flows and directly learns the signed UPNL or unrealized-loss snapshot.
- Recommendation: Move private risk values to encrypted inputs or another non-public verification design, or explicitly classify these values as public.

### H-02: Signed MPC accounting uses unchecked arithmetic

- Severity: High
- Summary: Signed encrypted accounting uses unchecked add, subtract, and multiply operations.
- Description: Core accounting code performs signed encrypted additions, subtractions, and multiplications on values that directly affect balances, settlement deltas, realized PnL, and liquidation results. The code uses unchecked signed encrypted operations in places where the result is later treated as valid protocol accounting state. If a signed encrypted intermediate crosses the signed range, the result can wrap instead of reverting.

  This is not only a theoretical arithmetic cleanliness issue. The affected operations are in shared libraries that update allocated balances and decide whether a position close, settlement, or liquidation is solvent. Any wrapped value can therefore move from a local calculation into persistent accounting or a branch condition that controls payouts. Code references: `contracts/libraries/LibAccount.sol:72`, `contracts/libraries/LibSettlement.sol:89`, `contracts/libraries/LibSettlement.sol:115`, `contracts/libraries/LibQuote.sol:237`, `contracts/libraries/LibQuote.sol:238`.
- Impact: If encrypted signed values cross the signed range, arithmetic can wrap and produce incorrect balances, settlement amounts, or solvency results.
- Attack path: A trader drives encrypted accounting values close to the signed boundary through normal quote or settlement flows, causing a later signed operation to wrap.
- Recommendation: Use checked signed encrypted arithmetic or prove strict value bounds before unchecked signed operations.

### H-04: Force-close price checks run before Muon signature verification

- Severity: High
- Summary: Force-close logic decrypts private price predicates before authenticating the Muon price signature.
- Description: The force-close implementation evaluates private price predicates before authenticating the price data used in those predicates. It compares caller-supplied public high, low, and average prices against the encrypted requested close price, decrypts the boolean results, and only later verifies the Muon high-low signature. This reverses the usual order for privacy-sensitive checks: unauthenticated data should not be allowed to influence decrypted predicates.

  Because the comparison result can cause different revert behavior, a caller does not need a valid Muon signature to learn information. They can submit chosen public prices and invalid signature data, then observe whether execution reaches the later signature check or reverts earlier due to a private predicate. Code references: `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:88`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:105`, `contracts/libraries/muon/LibMuonForceActions.sol:12`, `contracts/libraries/muon/LibMuonForceActions.sol:39`.
- Impact: Revert behavior becomes an oracle over the encrypted requested close price.
- Attack path: A caller submits fake signature data with chosen public prices and observes which check reverts, learning whether the chosen prices cross the private close threshold.
- Recommendation: Authenticate the Muon signature before decrypting or branching on any private price predicate.

### H-05: PartyA liquidation exposes plaintext risk snapshots

- Severity: High
- Summary: PartyA liquidation stores and returns risk snapshots as plaintext.
- Description: PartyA liquidation still uses a legacy plaintext `LiquidationDetail` struct for key risk snapshot fields. Normal and deferred liquidation copy UPNL and total unrealized loss from the Muon liquidation data into public signed fields even though related balance and liquidation values have encrypted replacements elsewhere in the fork. The liquidation detail is also part of the public view surface.

  This creates a mixed privacy model inside the same liquidation flow. Some liquidation values are moved to encrypted storage/events, while other closely related risk values remain readable through calldata, storage-backed views, or indexer state. Code references: `contracts/storages/AccountStorage.sol:29`, `contracts/storages/AccountStorage.sol:32`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:128`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:131`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:66`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:69`.
- Impact: Liquidation PnL and unrealized-loss snapshots are visible through calldata, storage-backed views, and indexed state.
- Attack path: Any observer reads the liquidation transaction or liquidation detail view and learns the PartyA risk snapshot.
- Recommendation: Remove plaintext risk fields from public liquidation structs or replace them with encrypted/observer-specific values.

### H-06: Account allocation events leak private balance deltas

- Severity: High
- Summary: Allocation and transfer events emit private account movement amounts in plaintext.
- Description: The allocated-balance ledger is encrypted in storage, but the account event layer was not updated to match that privacy boundary. Allocation, deallocation, internal transfer, multi-account allocation, and transfer-allocation paths still emit the moved amount as a plaintext event field. Since events are permanently public, the log stream becomes a readable record of the same account deltas that encrypted storage is intended to hide.

  The issue is structural because it exists in the shared account event interfaces and in multiple callers, not only in a single operation. Even if view functions are restricted or storage is unreadable, an indexer can reconstruct account movement history from events alone. Code references: `contracts/facets/Account/IAccountEvents.sol:12`, `contracts/facets/Account/IAccountEvents.sol:13`, `contracts/interfaces/IMultiAccount.sol:19`, `contracts/facets/Account/AccountFacet.sol:55`, `contracts/facets/Account/AccountFacet.sol:93`, `contracts/multiAccount/MultiAccount.sol:264`.
- Impact: Logs reveal account ledger deltas even when final balances are encrypted.
- Attack path: An indexer reconstructs private account movements from public `Allocate`, `Deallocate`, internal-transfer, and multi-account logs.
- Recommendation: Emit encrypted balance-change events or explicitly define these account movement amounts as public.

### H-07: Reserve vault and fee collector events leak private accounting amounts

- Severity: High
- Summary: Reserve and fee accounting is encrypted in storage but exposed in events.
- Description: Reserve vault and fee collector balances are updated through encrypted storage helpers, but the corresponding event layer still exposes movement amounts as ordinary public values. Reserve deposits, reserve withdrawals, and fee collector claims therefore publish the exact amount being moved even though the resulting reserve or fee balance is ciphertext.

  This is a direct privacy mismatch between storage and logs. If reserve usage and fee accruals are meant to be private protocol accounting values on COTI, plaintext events defeat that design because logs are easier to index than storage and cannot be hidden after emission. Code references: `contracts/facets/Account/IAccountEvents.sol:24`, `contracts/facets/Account/IAccountEvents.sol:25`, `contracts/facets/Account/AccountManagementFacet.sol:18`, `contracts/facets/Account/AccountManagementFacet.sol:25`, `contracts/libraries/LibEncryption.sol:98`, `contracts/libraries/LibEncryption.sol:103`.
- Impact: Public logs reveal exact reserve and fee movement amounts.
- Attack path: An observer monitors reserve and fee events and learns private accounting changes from event fields.
- Recommendation: Use encrypted event fields for reserve and fee movements or classify these amounts as public.

### H-08: Account balance checks expose threshold oracles through revert order

- Severity: High
- Summary: Some private balance predicates are decrypted before cheaper public balance checks finish.
- Description: Some account flows evaluate predicates over encrypted balances before completing cheaper public checks. In `allocate`, the encrypted allocated-balance limit is decrypted before the caller's plaintext free balance is checked. In `internalTransfer`, the recipient's encrypted balance-limit headroom is checked before the sender's ordinary deposited balance is confirmed. Since these encrypted comparisons are decrypted into branch conditions, the relative order of failures can reveal whether the private predicate passed.

  Private predicate checks should be placed after public authorization, signature, and caller-balance checks whenever possible. Otherwise an attacker can use calls that are expected to fail for public reasons as probes against another encrypted account property. Code references: `contracts/facets/Account/AccountFacetImpl.sol:52`, `contracts/facets/Account/AccountFacetImpl.sol:59`, `contracts/facets/Account/AccountFacetImpl.sol:61`, `contracts/facets/Account/AccountFacetImpl.sol:140`, `contracts/facets/Account/AccountFacetImpl.sol:146`, `contracts/facets/Account/AccountFacetImpl.sol:148`.
- Impact: Revert ordering can expose private balance thresholds and account headroom.
- Attack path: A caller varies public amounts in simulations or failed transactions and observes which revert occurs first.
- Recommendation: Run public authorization, caller-balance, and signature checks before decrypting private predicates.

### H-11: Settlement events publish encrypted opened prices in plaintext

- Severity: High
- Summary: Settlement logs reveal the opened prices that are stored as encrypted quote state.
- Description: Settlement updates each quote's `openedPrice` as encrypted quote state, but the event emitted by the settlement facets includes the same `updatedPrices` as a public `uint256[]`. The code therefore stores a value privately and simultaneously publishes it in the transaction log, making the encrypted storage field ineffective for opened-price privacy.

  This leak affects every quote included in a settlement batch. Any system indexing `SettleUpnl` can read the post-settlement opened price without needing view access, observer keys, or decryption. Code references: `contracts/facets/Settlement/SettlementFacetEvents.sol:11`, `contracts/facets/Settlement/SettlementFacetEvents.sol:13`, `contracts/facets/Settlement/SettlementFacet.sol:38`, `contracts/facets/Settlement/SettlementFacet.sol:40`, `contracts/libraries/LibSettlement.sol:67`, `contracts/libraries/LibSettlement.sol:77`.
- Impact: Every settlement publicly reveals the new opened price for each affected quote.
- Attack path: Any observer reads the `SettleUpnl` log and obtains the updated opened prices.
- Recommendation: Remove plaintext opened prices from settlement events or replace them with encrypted event data.

### H-12: `settleAndForceClosePosition` settles against the caller instead of the quote PartyA

- Severity: High
- Summary: Settlement-backed force close passes `msg.sender` where the quote PartyA is required.
- Description: The settlement-backed force-close path is intended to execute a close while also settling related UPNL, but it passes `msg.sender` into settlement as the PartyA. The settlement library then validates that each settled quote belongs to that address. This is incorrect for a permissionless force-close function, because the caller can be a third party and does not have to be the quote's actual PartyA.

  As a result, the settlement subflow can reject otherwise valid force-close attempts or emit/account against the wrong address context. The correct PartyA is already available from the quote being force-closed and should be used consistently throughout the settlement branch. Code references: `contracts/facets/ForceActions/SettleAndForceCloseFacet.sol:26`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:179`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:180`, `contracts/libraries/LibSettlement.sol:53`.
- Impact: Permissionless force close with settlement reverts for callers other than the actual PartyA, and related event/account data can point to the wrong address.
- Attack path: A third party attempts to force-close a close-pending quote with settlement data, but the settlement subcall checks ownership against the third party.
- Recommendation: Pass the quote's PartyA into settlement, or restrict this path to the quote PartyA and make that requirement explicit.

### H-13: Deposited free collateral and bridge amounts remain plaintext

- Severity: High
- Summary: Free collateral and bridge ledgers remain public while other account balances are encrypted.
- Description: The fork encrypts allocated, locked, reserve, and fee balances, but leaves the deposited free-collateral ledger as a plaintext `uint256` mapping. Deposit, withdrawal, bridge, event, and view paths all interact with that plaintext ledger. This means unallocated user collateral remains publicly visible even though other parts of the same account balance model are encrypted.

  The privacy boundary is therefore inconsistent at the account level. A user's allocated and locked balances may be ciphertext, but observers can still track free collateral movements and infer part of the user's account state and trading readiness. Code references: `contracts/storages/AccountStorage.sol:52`, `contracts/storages/AccountStorage.sol:53`, `contracts/facets/Account/AccountFacetImpl.sol:26`, `contracts/facets/Account/AccountFacetImpl.sol:30`, `contracts/facets/ViewFacet/ViewFacet.sol:30`, `contracts/facets/ViewFacet/ViewFacet.sol:31`.
- Impact: User free collateral and bridge movements are publicly visible.
- Attack path: An observer reads deposits, withdrawals, bridge transfers, and account balance views to reconstruct unallocated collateral.
- Recommendation: Encrypt the free-collateral ledger or document free collateral and bridge amounts as public.

### H-14: Force-close liquidation ignores reserve credit when computing PartyB deficit

- Severity: High
- Summary: Force-close PartyB liquidation uses an old available-balance value after reserve credit changes state.
- Description: During force-close-triggered PartyB liquidation, the code can apply PartyB reserve credit by zeroing the reserve vault and increasing PartyB's allocated balance. However, it continues into the liquidation helper with an available-balance value that was computed before this reserve credit. The helper therefore receives a stale deficit input while storage already reflects the reserve movement.

  This produces inconsistent accounting inside a sensitive insolvency path. The same liquidation branch uses current storage for some values and the pre-reserve snapshot for others, so deficit, remaining LF, liquidator share, and PartyA recovery can all be derived from a state that never actually existed. Code references: `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:160`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:185`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:208`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:213`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:219`, `contracts/libraries/LibLiquidation.sol:49`, `contracts/libraries/LibLiquidation.sol:55`.
- Impact: PartyB deficit, remaining LF, liquidator share, and PartyA recovery can be calculated from inconsistent state.
- Attack path: A public force close makes PartyB insolvent while reserve only partially covers the deficit; liquidation then computes recovery using the old deficit input.
- Recommendation: Recompute available balance after reserve credit or pass one consistent liquidation snapshot through the full branch.

### H-15: PartyB liquidation can revert when remaining LF exceeds allocated balance

- Severity: High
- Summary: PartyB insolvency can be proven even though the later LF subtraction cannot be paid from allocated balance.
- Description: PartyB insolvency is determined from a formula that includes allocated balance, locked CVA/LF, and UPNL, but the later liquidation payout assumes the remaining LF can be subtracted from current allocated balance. These are not equivalent conditions. A PartyB can be insolvent under the formula while still not having enough allocated balance to pay the computed remaining LF.

  The problematic case occurs when positive UPNL offsets part of the formula but LF is still larger than the allocated collateral available for the later subtraction. The code proves insolvency, then reaches a checked subtraction that can revert, preventing the liquidation path from completing. Code references: `contracts/libraries/LibAccount.sol:225`, `contracts/libraries/LibAccount.sol:232`, `contracts/libraries/LibLiquidation.sol:49`, `contracts/libraries/LibLiquidation.sol:55`, `contracts/libraries/LibLiquidation.sol:96`, `contracts/libraries/LibLiquidation.sol:97`.
- Impact: Liquidation reverts even though PartyB is insolvent, leaving the unhealthy state unresolved until balances or market state change.
- Attack path: PartyB becomes insolvent with positive UPNL but LF larger than allocated balance; the `checkedSub` of remaining LF reverts during liquidation.
- Recommendation: Cap remaining LF to payable allocated balance or handle the positive-UPNL insolvency case separately.

### H-16: Deferred liquidation type uses current balance instead of the signed snapshot

- Severity: High
- Summary: Deferred liquidation proves insolvency from a historical signed balance but classifies liquidation from current encrypted balance.
- Description: Deferred liquidation correctly receives a signed historical allocated-balance snapshot, but only uses that snapshot for the initial insolvency proof. After that proof, reimbursement and liquidation-type logic recompute availability from the current encrypted allocated balance. If the account changes between the signed snapshot and execution, the type and payout calculations are no longer tied to the state that Muon certified as insolvent.

  This breaks the purpose of deferred liquidation data. The signature is meant to authorize liquidation based on a specific historical state, but the contract mixes that historical UPNL with current balance storage, allowing NORMAL/LATE/OVERDUE classification and accounting values to drift from the signed snapshot. Code references: `contracts/storages/MuonStorage.sol:67`, `contracts/storages/MuonStorage.sol:72`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:39`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:41`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:49`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:52`.
- Impact: Balance changes between snapshot and execution can change NORMAL, LATE, or OVERDUE classification and alter liquidation accounting.
- Attack path: After a deferred liquidation snapshot is signed, the account balance changes; the old signature is submitted and the contract classifies liquidation using the new balance.
- Recommendation: Use the same signed snapshot for both insolvency proof and liquidation type/accounting.

### H-26: Force-close PartyB liquidation uses a post-close balance without closing the quote

- Severity: High
- Summary: Force-close-triggered PartyB liquidation mixes post-close availability with pre-close quote storage.
- Description: The force-close path calculates PartyB availability using a helper that models the requested close as already applied, including proportional unlocks and close-price PnL. If that simulated post-close availability shows PartyB as insolvent, the code enters PartyB liquidation before actually closing the quote in storage. The liquidation helper then operates while the quote and its locked balances still exist as open state.

  This creates an accounting mismatch between the input used to trigger liquidation and the storage read during liquidation. Liquidation results depend on whether the quote is considered open or closed, so mixing a post-close availability value with pre-close locked state can understate or misallocate the insolvency amounts. Code references: `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:160`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:178`, `contracts/libraries/LibSolvency.sol:183`, `contracts/libraries/LibSolvency.sol:186`, `contracts/libraries/LibLiquidation.sol:49`, `contracts/libraries/LibLiquidation.sol:55`.
- Impact: Deficit, remaining LF, liquidator reward, and PartyA payout can be calculated from mixed accounting states.
- Attack path: A force close makes PartyB insolvent; liquidation uses after-close availability while locked balances still reflect the open quote.
- Recommendation: Close/update the quote before liquidation accounting or compute liquidation entirely from pre-close state.

### H-27: Account balance deltas remain public calldata despite encrypted storage

- Severity: High
- Summary: Sensitive account movement amounts are still passed as public `uint256` calldata.
- Description: Many account movement APIs still accept the moved amount as a public `uint256` even though the state being modified is encrypted. Calldata is public on-chain data, so allocation, deallocation, internal transfer, PartyB allocation transfer, reserve movement, and fee-collector claim amounts are disclosed before the contract writes encrypted storage or emits any encrypted event.

  This is a separate privacy issue from event leakage because it exists even if all events are fixed. The ABI itself exposes the balance delta, so any user or indexer watching transaction input data can reconstruct movements across the encrypted account ledger. Code references: `contracts/facets/Account/AccountFacet.sol:49`, `contracts/facets/Account/AccountFacet.sol:87`, `contracts/facets/Account/AccountManagementFacet.sol:16`, `contracts/facets/Account/AccountManagementFacet.sol:23`, `contracts/facets/Account/AccountFacetImpl.sol:53`, `contracts/facets/Account/AccountFacetImpl.sol:77`.
- Impact: Transaction input data reveals exact balance deltas.
- Attack path: An observer reads transaction calldata for account movement calls and reconstructs private balance changes.
- Recommendation: Use encrypted COTI inputs for sensitive deltas or explicitly define these deltas as public.

### H-28: Quote views expose COTI system ciphertexts

- Severity: High
- Summary: Public quote views return full encrypted quote structs, including internal system ciphertext fields.
- Description: Quote numeric fields are stored in `utUint256` structs, which carry ciphertext data used by the protocol and user-facing encryption model. Public view functions return entire stored `Quote` structs for individual quotes, quote ranges, and open positions instead of returning a redacted view type. This exposes ciphertext material for requested prices, opened prices, quantities, close prices, locked values, and fees to arbitrary callers.

  A privacy-preserving view layer should decide which ciphertext, if any, is safe for a given caller. Returning the raw storage struct makes the internal encrypted representation part of the public API and defeats that separation. Code references: `contracts/storages/QuoteStorage.sol:69`, `contracts/storages/QuoteStorage.sol:76`, `contracts/facets/ViewFacet/ViewFacet.sol:456`, `contracts/facets/ViewFacet/ViewFacet.sol:457`, `contracts/facets/ViewFacet/ViewFacet.sol:531`.
- Impact: Callers receive ciphertext material for private quote state that should not be exposed through public views.
- Attack path: A caller invokes quote or position views and collects ciphertexts for requested/opened/close prices, quantity, locked values, and fees.
- Recommendation: Return redacted structs or reader-specific ciphertext only; never expose internal system ciphertext through public views.

### H-32: Emergency close is blocked when a party is already insolvent

- Severity: High
- Summary: Emergency close still requires both sides to satisfy normal solvency constraints.
- Description: Emergency close is intended as a recovery mechanism during emergency mode, PartyB emergency mode, or symbol invalidation. However, the implementation still enforces ordinary solvency preconditions and then routes through the standard close accounting path. If either party is already insolvent, the same checks that block normal close can also block emergency close.

  This makes the recovery action unavailable in one of the main states where a recovery action is needed. A dedicated emergency close should either define how deficits are handled or route through reserve/liquidation logic, rather than requiring both parties to be solvent before recovery can proceed. Code references: `contracts/facets/RecoveryActions/RecoveryActionsFacet.sol:28`, `contracts/facets/RecoveryActions/RecoveryActionsFacet.sol:31`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacetImpl.sol:84`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacetImpl.sol:105`, `contracts/libraries/LibQuote.sol:237`, `contracts/libraries/LibQuote.sol:238`.
- Impact: Emergency close can fail exactly when recovery is needed, leaving positions stuck.
- Attack path: Emergency mode is enabled or a symbol is invalidated while one party is insolvent; emergency close reverts on solvency checks.
- Recommendation: Define an emergency settlement path that can close insolvent positions and route deficits through reserve/liquidation handling.

### H-33: Fee distributor cannot claim encrypted fee accruals

- Severity: High
- Summary: Fees accrue in encrypted fee collector storage but the distributor withdraws from plaintext free balance.
- Description: Trading fees accrue to fee collectors in encrypted fee-collector storage, and a separate protocol call is required to move those fees into withdrawable free balance. `SymmioFeeDistributor` is written against the normal withdrawal model and assumes claimable fees are already available through that path. If the distributor address is configured as a fee collector, fees can accrue to encrypted storage that the distributor never claims before attempting distribution.

  The issue is an integration mismatch between the COTI fork's encrypted fee accounting and the external distributor's legacy balance assumptions. The distributor can appear correctly configured but still be unable to claim or distribute fees that are present only as encrypted fee collector balance. Code references: `contracts/libraries/LibPartyBPositionsActions.sol:50`, `contracts/libraries/LibPartyBPositionsActions.sol:70`, `contracts/facets/Account/AccountManagementFacet.sol:30`, `contracts/facets/Account/AccountFacetImpl.sol:218`, `contracts/facets/Account/AccountFacetImpl.sol:221`, `contracts/facets/Account/AccountFacetImpl.sol:225`, `contracts/facets/Account/AccountFacetImpl.sol:226`, `contracts/SymmioFeeDistributor.sol:154`, `contracts/SymmioFeeDistributor.sol:157`, `contracts/SymmioFeeDistributor.sol:168`, `contracts/SymmioFeeDistributor.sol:173`.
- Impact: Fees can remain stuck in Symmio encrypted fee storage when the distributor is configured as a fee collector.
- Attack path: Fees accrue to the distributor's encrypted fee balance; `claimAllFee()` sees no plaintext free balance and `claimFee(amount)` reverts or underclaims.
- Recommendation: Add an encrypted fee-collector claim step to the distributor or align fee accrual with the distributor's withdrawal model.

### H-34: Expired close requests can still be force closed after their deadline

- Severity: High
- Summary: Force close validates the signed price window against the deadline but not the current execution time.
- Description: The close-request lifecycle treats the quote deadline as the point after which the request should expire. The cancel-close path explicitly expires the quote when current time is past that deadline. Force close, however, only checks that the signed high-low price window ended before the deadline; it does not check that the force-close transaction itself is submitted before the deadline.

  As a result, an expired close request can remain executable through force close if the caller provides price data from a window that was valid before expiry. This preserves stale optionality beyond the deadline that other parts of the lifecycle treat as final. Code references: `contracts/facets/PartyA/PartyAFacetImpl.sol:224`, `contracts/facets/PartyA/PartyAFacetImpl.sol:249`, `contracts/facets/PartyA/PartyAFacetImpl.sol:256`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:82`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:84`.
- Impact: PartyA can execute a stale close request after it should have expired.
- Attack path: PartyA creates a close request with deadline `D`, waits until after `D`, then submits a high-low signature whose price window ended before `D`.
- Recommendation: Require `block.timestamp <= quote.deadline` before force close or expire the quote before force-close execution.

### H-35: Permissionless force close can capture the PartyB liquidation reward

- Severity: High
- Summary: Force-close-triggered PartyB liquidation pays the liquidator share to the arbitrary force-close caller.
- Description: Direct PartyB liquidation is restricted to authorized liquidators, but permissionless force close can enter the same PartyB liquidation helper when the close makes PartyB insolvent. The helper credits the liquidator share to `allocatedBalances[msg.sender]`. In the direct liquidation path that caller is role-restricted, but in the force-close path it can be any public account.

  This creates an authorization bypass for the reward recipient, not necessarily for the liquidation decision itself. A public caller can execute a valid force close and receive a reward that the normal PartyB liquidation entry point only allows authorized liquidators to receive. Code references: `contracts/facets/ForceActions/ForceCloseFacet.sol:23`, `contracts/facets/ForceActions/SettleAndForceCloseFacet.sol:26`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:177`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:183`, `contracts/facets/liquidation/LiquidationFacet.sol:121`, `contracts/libraries/LibLiquidation.sol:131`.
- Impact: A public caller can capture the liquidation reward intended for authorized liquidation flow. The value is bounded by the configured liquidator share.
- Attack path: A caller races or copies a force-closeable transaction that makes PartyB insolvent and receives the liquidation share as `msg.sender`.
- Recommendation: Pay force-close-triggered liquidation rewards to an authorized liquidator, protocol reserve, or deterministic recipient.

### H-38: Zero-CVA liquidations can select LATE and divide by zero

- Severity: High
- Summary: Liquidation can enter the LATE branch with total CVA equal to zero.
- Description: Quote validation allows positions with zero CVA, but liquidation classification and LATE liquidation math assume total CVA can be used as a denominator. If a PartyA has only zero-CVA positions and the deficit equals LF, the type selection can choose LATE because the deficit is not below LF but is still within LF plus CVA. The later LATE branch then calculates adjusted CVA by dividing by total CVA, which is zero.

  This is a lifecycle consistency bug between quote validation and liquidation settlement. Either zero CVA should be disallowed for positions that can enter this liquidation path, or liquidation must handle the zero-CVA case without using CVA as a denominator. Code references: `contracts/facets/PartyA/PartyAFacetImpl.sol:78`, `contracts/facets/PartyA/PartyAFacetImpl.sol:81`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:167`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:171`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:300`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:301`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:107`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:111`.
- Impact: PartyA liquidation settlement can revert at the exact LF boundary.
- Attack path: PartyA opens zero-CVA positions; liquidation later produces a deficit exactly equal to LF, selecting LATE and dividing by zero.
- Recommendation: Require non-zero total CVA where LATE liquidation depends on it, or add a zero-CVA liquidation branch.

### M-02: Same-timestamp old liquidation prices can be reused

- Severity: Medium
- Summary: Liquidation symbol prices are keyed by timestamp rather than a unique liquidation identifier.
- Description: Liquidation symbol prices are stored by PartyA and symbol with only a timestamp freshness check, and cleanup does not clear those stored prices after liquidation finishes. A later liquidation for the same PartyA and symbol can accept the old price if the new liquidation detail has the same timestamp. The price is not bound to a unique liquidation instance or nonce.

  Timestamp equality is too weak as the only association between a stored price and a liquidation. If the same timestamp is reused by valid signed data, stale `symbolsPrices` state can satisfy the final liquidation price check without a fresh price-setting transaction for that liquidation. Code references: `contracts/storages/AccountStorage.sol:43`, `contracts/storages/AccountStorage.sol:45`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:156`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:254`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:502`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:509`.
- Impact: A later liquidation with the same timestamp can reuse stale symbol prices.
- Attack path: A PartyA enters a new liquidation with the same timestamp as an older one; old symbol prices still satisfy the timestamp check.
- Recommendation: Bind symbol prices to a liquidation id or clear all related symbol prices during cleanup.

### M-03: Liquidation dispute accumulator ignores CVA released at settlement

- Severity: Medium
- Summary: Dispute accounting compares expected settlement amounts without including CVA release.
- Description: The liquidation dispute accumulator attempts to compare expected settlement results against signed liquidation data, but it only accumulates PartyB settlement `expectedAmount` values. The actual settlement path can also release CVA, meaning the accumulator and the final settlement logic are not measuring exactly the same economic movement.

  This can cause the dispute check to flag a liquidation even when the full settlement path would be consistent after CVA effects are included. The accumulator should match the real settlement formula, including all collateral components that affect final balances. Code references: `contracts/facets/liquidation/LiquidationFacetImpl.sol:88`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:90`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:95`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:99`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:414`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:416`.
- Impact: Liquidation can be marked disputed even when final settlement would be consistent.
- Attack path: Final liquidation settlement includes CVA effects, but the dispute accumulator sees only capped expected amounts and flags a mismatch.
- Recommendation: Include all collateral movements that affect settlement consistency, including CVA release.

### M-10: Suspension does not block several user state-changing paths

- Severity: Medium
- Summary: Suspended PartyA accounts can still perform several state-changing actions.
- Description: The suspension mechanism is applied to some user actions but not consistently across all PartyA-controlled state transitions. A suspended PartyA can still change account allocation or quote lifecycle state through paths such as deallocation, quote cancellation requests, position close requests, and close-request cancellation. These are meaningful state changes even if new quote creation or withdrawals are blocked.

  If suspension is intended as a risk-control freeze for a PartyA, every user-controlled action that changes balance allocation or quote state needs to share the same guard. Otherwise suspension leaves operational gaps that can be used to change protocol state during an intervention. Code references: `contracts/facets/Control/ControlFacet.sol:473`, `contracts/facets/Control/ControlFacet.sol:478`, `contracts/facets/Account/AccountFacet.sol:87`, `contracts/facets/PartyA/PartyAFacet.sol:161`, `contracts/facets/PartyA/PartyAFacet.sol:182`, `contracts/facets/PartyA/PartyAFacet.sol:242`.
- Impact: Suspension is incomplete as a risk-control mechanism.
- Attack path: A suspended PartyA changes allocation or quote lifecycle state through an unguarded path.
- Recommendation: Apply suspension checks consistently or document which actions remain allowed during suspension.

### M-11: Global pause does not stop internal transfers

- Severity: Medium
- Summary: Internal transfer pause logic does not include global pause.
- Description: Most pause modifiers include the global pause flag, but the internal-transfer-specific modifier only checks the internal-transfer and accounting pause flags. `internalTransfer` uses that narrower modifier, so activating global pause alone does not stop this balance-moving path. This makes global pause less global than its name and surrounding pause model imply.

  During an incident, operators may reasonably expect `pauseGlobal()` to stop user-controlled fund movement. If internal transfers should remain available during global pause, that exception should be explicit; otherwise the modifier should include `globalPaused`. Code references: `contracts/utils/Pausable.sol:10`, `contracts/utils/Pausable.sol:12`, `contracts/facets/Control/ControlFacet.sol:389`, `contracts/facets/Control/ControlFacet.sol:391`, `contracts/facets/Account/AccountFacet.sol:107`, `contracts/facets/Account/AccountFacet.sol:110`.
- Impact: `pauseGlobal()` does not freeze internal transfers unless another pause flag is also enabled.
- Attack path: During a global pause, users continue moving allocated balances through `internalTransfer`.
- Recommendation: Include `globalPaused` in the internal-transfer pause modifier if global pause is intended to freeze all user fund movement.

### M-13: Trusted observer rotation does not re-encrypt existing observer state

- Severity: Medium
- Summary: Changing the trusted observer only affects future ciphertexts.
- Description: The trusted observer address controls how future observer ciphertexts are produced, but rotating the address does not migrate ciphertext already stored for balances, quotes, locked values, or settlement state. Existing observer ciphertext remains encrypted for the previous observer, or remains unset if no observer existed when the value was written. The setter therefore changes future encryption behavior but does not make current protocol state readable to the new observer.

  This is an availability and monitoring issue for any system relying on observer views. After rotation, the observer's view of state can be incomplete until each value is touched by a later write path, and there is no single contract-level migration that re-encrypts all outstanding observer state. Code references: `contracts/facets/Control/ControlFacet.sol:527`, `contracts/facets/Control/ControlFacet.sol:533`, `contracts/libraries/LibEncryption.sol:34`, `contracts/libraries/LibEncryption.sol:47`, `contracts/facets/ViewFacet/ViewFacet.sol:460`, `contracts/facets/ViewFacet/ViewFacet.sol:466`.
- Impact: A new observer cannot reliably decrypt existing balances, quotes, and locked-value state until later writes occur.
- Attack path: After observer rotation, monitoring reads observer views and receives ciphertext intended for the old observer.
- Recommendation: Add a migration/re-encryption process or document observer rotation as forward-only.

### M-14: Observer balance-change events are missing for non-accounting balance mutations

- Severity: Medium
- Summary: Several encrypted balance mutations update storage without matching observer event coverage.
- Description: The observer event stream is only partially implemented for encrypted balance changes. Allocation and deallocation emit observer-readable balance events, but other important balance mutations, including fees, realized PnL, liquidation changes, reserve-backed force close, and liquidation-fee payments, update storage without the same observer event coverage. The observer may receive user-facing encrypted events, but not the observer-specific ciphertext needed for event-only reconstruction.

  This creates divergence between storage truth and log-derived observer state. Any monitor that processes observer events without polling all affected views after every transaction can miss material balance changes. Code references: `contracts/libraries/SharedEvents.sol:29`, `contracts/libraries/SharedEvents.sol:31`, `contracts/facets/Account/AccountFacet.sol:57`, `contracts/facets/Account/AccountFacet.sol:77`, `contracts/libraries/LibQuote.sol:253`, `contracts/libraries/LibQuote.sol:263`.
- Impact: Observer systems following logs can miss material balance changes.
- Attack path: An observer indexer reconstructs balances from events and misses fee, PnL, liquidation, or reserve-backed changes.
- Recommendation: Emit observer-encrypted balance-change events for every encrypted balance mutation or require polling.

### M-15: `priceValidTime` is configured but not enforced

- Severity: Medium
- Summary: Price freshness configuration is stored but not consistently used.
- Description: The Muon configuration exposes both UPNL and price freshness settings, but price-bearing verification paths do not consistently enforce the dedicated `priceValidTime` value. Some verification logic relies on other windows or on later path-specific checks instead of applying the configured price-validity bound. This creates a mismatch between the configuration surface and the actual freshness rules.

  Operators and integrators can reasonably assume that lowering `priceValidTime` tightens all price signature acceptance. If the setting is not consistently used, stale-price risk depends on code-path-specific behavior rather than the central Muon configuration. Code references: `contracts/storages/MuonStorage.sol:139`, `contracts/storages/MuonStorage.sol:140`, `contracts/facets/Control/ControlFacet.sol:106`, `contracts/facets/Control/ControlFacet.sol:110`, `contracts/libraries/muon/LibMuonPartyA.sol:15`, `contracts/libraries/muon/LibMuonPartyB.sol:13`.
- Impact: Operators may believe price signatures are bounded by `priceValidTime` when that setting has no consistent effect.
- Attack path: A caller submits a price-bearing Muon signature accepted by another window or by no standalone price-validity check.
- Recommendation: Enforce `priceValidTime` on every price-bearing signature path or remove the unused setting.

### M-16: Public liquidation type leaks the private deficit range

- Severity: Medium
- Summary: Public liquidation type reveals a range over encrypted deficit magnitude.
- Description: Liquidation type is derived by decrypting comparisons between the private encrypted deficit and encrypted LF/CVA thresholds. The resulting `LiquidationType` is stored as public state and used by later liquidation logic. Even if the exact deficit remains encrypted, the public type discloses the range in which the private deficit falls.

  This may be an intentional lifecycle disclosure, but it should be treated as a privacy decision rather than an implementation detail. On a privacy-focused COTI fork, bucketed disclosure of private deficit magnitude can still be meaningful information about the account's loss state. Code references: `contracts/facets/liquidation/LiquidationFacetImpl.sol:169`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:170`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:109`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:110`.
- Impact: Observers learn whether the private deficit is below LF, between LF and LF plus CVA, or above that range.
- Attack path: Anyone reads liquidation state or views after liquidation and infers the deficit range from the public type.
- Recommendation: Treat liquidation type as intentional public disclosure or redesign classification to avoid range leakage.

### M-22: COTI dependencies are floating Git branches

- Severity: Medium
- Summary: COTI dependencies are not pinned to immutable versions.
- Description: The project references COTI packages through moving Git branch names and does not track a lockfile that pins the exact resolved dependency revisions. Because the contracts rely on COTI helper semantics for encrypted types, onboarding/offboarding, and MPC operations, dependency changes can alter the build and runtime assumptions without any Solidity source diff in this repository.

  This weakens reproducibility for audits, deployments, and incident response. A clean install performed later may not correspond to the reviewed dependency code, which is especially risky for a chain-specific privacy fork whose correctness depends on external cryptographic helper behavior. Code references: `package.json:10`, `package.json:11`, `.gitignore:2`.
- Impact: Clean installs can resolve different dependency code and change encrypted helper behavior without a repository source diff.
- Attack path: A later install resolves updated dependency branches, producing different build/test/deployment behavior from the reviewed code.
- Recommendation: Pin dependencies to immutable commits or versions and track the lockfile used for builds.

### M-23: Observer events are missing for partial-fill child quotes

- Severity: Medium
- Summary: Partial-fill child quote creation omits trusted-observer event coverage.
- Description: Partial-fill execution can create a child quote with private quote fields derived from the original quote. The path emits PartyA and PartyB events for that child quote, but it does not emit the corresponding observer-encrypted quote event that observer systems would need to reconstruct the child from logs. This creates an event coverage gap specifically for split/partial-fill lifecycle transitions.

  If the trusted observer is expected to monitor private quote state from events, normal quote creation and partial-fill child creation need equivalent observer event surfaces. Otherwise the observer can see the parent flow but miss the child quote unless it performs additional view polling. Code references: `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacet.sol:46`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacet.sol:49`, `contracts/facets/PartyBGroupActions/PartyBGroupActionsFacetImpl.sol:61`, `contracts/facets/PartyBGroupActions/PartyBGroupActionsFacetImpl.sol:96`.
- Impact: Observer indexers that rely on events can miss child quote state.
- Attack path: A partial fill creates a child quote, but the observer event stream does not include the observer-encrypted child quote data.
- Recommendation: Emit observer-encrypted child quote events on partial-fill creation.

### M-24: Emergency close emits the close price as plaintext

- Severity: Medium
- Summary: Emergency close leaks the execution price through a public event field.
- Description: Normal close and force-close events use encrypted event data for close amounts and prices, but the emergency-close event keeps the close price as a public integer. Emergency close still closes an economically sensitive position, so it should not have a weaker privacy boundary unless that disclosure is an intentional emergency-mode tradeoff.

  The inconsistency is easy to miss because the storage/accounting path is similar to other close paths, but the event ABI differs. Any emergency close therefore leaks execution price through logs even if ordinary close and force-close events are private. Code references: `contracts/facets/PartyBPositionActions/IPartyBPositionActionsEvents.sol:12`, `contracts/facets/PartyBPositionActions/IPartyBPositionActionsEvents.sol:17`, `contracts/facets/RecoveryActions/RecoveryActionsFacet.sol:39`, `contracts/facets/RecoveryActions/RecoveryActionsFacet.sol:45`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacetImpl.sol:95`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacetImpl.sol:110`.
- Impact: Emergency-close execution prices are publicly visible in logs.
- Attack path: Any observer reads emergency-close events and learns the exact close price.
- Recommendation: Encrypt emergency-close price event data or document emergency close as a public-price action.

### M-25: Encrypted balance-change events mix deltas and balance snapshots

- Severity: Medium
- Summary: The same encrypted event field is used for different accounting semantics.
- Description: The shared encrypted balance-change events use a generic `amount` field, but different paths put different semantics into that field. Settlement, PnL, fee, and liquidation paths emit deltas, while allocation/deallocation paths emit the resulting allocated-balance snapshot. A consumer cannot know from the field itself whether it should add the value to local state or replace local state with it.

  This is a data-model bug in the event schema. Even though the values are encrypted, the semantic mismatch still matters for wallets, observers, and indexers that process user-specific or observer-specific ciphertext and maintain off-chain accounting state. Code references: `contracts/libraries/SharedEvents.sol:25`, `contracts/libraries/SharedEvents.sol:27`, `contracts/facets/Account/AccountFacet.sol:53`, `contracts/facets/Account/AccountFacet.sol:56`, `contracts/libraries/LibSettlement.sol:126`, `contracts/libraries/LibSettlement.sol:137`.
- Impact: Indexers and UIs can miscompute balances unless they special-case event type semantics.
- Attack path: An indexer treats all balance-change amounts as deltas and drifts when allocation events provide snapshots.
- Recommendation: Split delta and snapshot events or add an explicit semantic field.

### M-26: `uint8` loop counters make large batches revert

- Severity: Medium
- Summary: Several batch loops use `uint8` counters for unbounded array lengths.
- Description: Several loops iterate over calldata or storage arrays using `uint8` counters even though the array lengths are not capped to 255 entries. Under Solidity 0.8 overflow checks, the counter overflows and reverts once it passes 255. The affected loops appear in account, PartyB, PartyA, control, settlement, and solvency-related code.

  This makes batch capacity depend on an unintended integer type rather than on explicit gas or protocol limits. If the protocol wants to limit batch sizes, it should validate those sizes directly; otherwise the loops should use `uint256` counters like normal Solidity iteration. Code references: `contracts/multiAccount/MultiAccount.sol:295`, `contracts/multiAccount/SymmioPartyB.sol:143`, `contracts/multiAccount/SymmioPartyB.sol:154`, `contracts/facets/PartyA/PartyAFacet.sol:143`, `contracts/facets/PartyA/PartyAFacetImpl.sol:103`, `contracts/facets/Control/ControlFacet.sol:228`, `contracts/libraries/LibSettlement.sol:50`, `contracts/libraries/LibSolvency.sol:118`.
- Impact: Valid batches longer than 255 entries revert under Solidity overflow checks.
- Attack path: A caller submits or creates a batch with more than 255 entries and the loop counter overflows.
- Recommendation: Use `uint256` counters for unbounded batch and array loops.

### M-34: Balance-change event types leak private PnL direction

- Severity: Medium
- Summary: Some encrypted amount events still reveal PnL direction through public event type.
- Description: The normal close path appears to avoid revealing PnL direction by emitting both PnL-in and PnL-out event shapes with one encrypted zero. Settlement and PartyA liquidation do not follow that constant-shape pattern. They branch and emit only the event type that matches the actual PnL direction, so the public event type leaks information even though the amount is encrypted.

  This is a privacy leak through metadata rather than through the encrypted value itself. Any observer can infer who gained or lost from event selection alone, without needing to decrypt the amount field. Code references: `contracts/libraries/LibQuote.sol:262`, `contracts/libraries/LibSettlement.sol:124`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:422`.
- Impact: Observers learn who gained or lost even without decrypting the amount.
- Attack path: An observer watches whether the emitted event type is `REALIZED_PNL_IN` or `REALIZED_PNL_OUT`.
- Recommendation: Use a constant event shape for all PnL paths when PnL direction is intended private.

### M-36: Deferred liquidation reimbursement can underflow when current availability exceeds allocated balance

- Severity: Medium
- Summary: Deferred liquidation subtracts current available balance from allocated balance without capping it.
- Description: Deferred liquidation mixes historical and current state when reimbursing available balance. After proving insolvency from a signed historical snapshot, it recomputes current availability from current allocated balance plus the signed UPNL. If that current availability is positive, the code subtracts the full available amount from allocated balance without capping it to the collateral actually held.

  Because availability can include positive UPNL, it can exceed allocated collateral. In that case, the reimbursement subtraction underflows and reverts instead of paying a capped amount or using the signed liquidation snapshot consistently. Code references: `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:49`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:53`, `contracts/libraries/LibAccount.sol:122`, `contracts/libraries/LibAccount.sol:124`.
- Impact: Positive UPNL can make current availability exceed allocated collateral and cause reimbursement subtraction to revert.
- Attack path: A deferred liquidation is executed after state changes make current availability greater than allocated balance.
- Recommendation: Cap reimbursement to allocated collateral or use the signed liquidation snapshot consistently.

### M-37: Liquidation dispute resolution accepts private settlement amounts as plaintext calldata

- Severity: Medium
- Summary: Dispute settlement amounts are public calldata before they are encrypted into state.
- Description: Liquidation dispute resolution writes final settlement amounts into encrypted settlement state, but the external function receives those amounts as public `int256[]` calldata. The values are therefore already disclosed to observers before the contract encrypts and stores them. Encryption after public submission does not restore confidentiality.

  This is similar to other calldata privacy breaks in the fork: moving a value into encrypted storage is insufficient if the ABI requires the caller to publish the value in plaintext first. Dispute resolution amounts should either be intentionally public or accepted through an encrypted input flow. Code references: `contracts/facets/liquidation/LiquidationResolutionFacet.sol:30`, `contracts/facets/liquidation/LiquidationResolutionFacet.sol:33`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:367`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:370`.
- Impact: Private dispute settlement amounts are visible in transaction input data.
- Attack path: Any observer reads the dispute-resolution transaction calldata and learns each settlement amount.
- Recommendation: Use encrypted inputs for private dispute settlement amounts or document those amounts as public.

### M-40: Trusted observer events are missing for position execution

- Severity: Medium
- Summary: Open and close execution paths update observer storage but do not emit observer execution events.
- Description: Position open and close execution paths update quote state and emit user-facing PartyA/PartyB events, but they do not emit observer-encrypted execution events for filled amount and execution price. Observer systems that rely on logs therefore receive quote creation and close-request information but not the final execution values in the same event model.

  This leaves the observer event stream incomplete around the most important lifecycle transition: execution. Without polling views after each transaction, an observer cannot reconstruct the full private quote lifecycle from events alone. Code references: `contracts/interfaces/IPartiesEvents.sol:39`, `contracts/interfaces/IPartiesEvents.sol:46`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacet.sol:39`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacet.sol:43`, `contracts/facets/PartyBPositionActions/PartyBCloseActionsFacet.sol:35`, `contracts/facets/PartyBPositionActions/PartyBCloseActionsFacet.sol:39`.
- Impact: Observer systems relying on logs cannot reconstruct execution details without polling views.
- Attack path: An observer indexer sees quote creation but misses encrypted execution values for later open or close fills.
- Recommendation: Emit observer-encrypted open and close execution events.

### M-44: Liquidation cleanup can leave observer ciphertext state stale

- Severity: Medium
- Summary: Some liquidation cleanup clears primary encrypted state without clearing matching observer state.
- Description: Most encrypted storage writes go through helpers that update both user-facing and observer-facing ciphertext, but some liquidation cleanup paths write or delete primary encrypted state directly. Pending PartyB locked balances and liquidation accumulator state can be cleared in primary storage while the matching observer ciphertext is left unchanged. That makes observer views disagree with primary protocol state.

  The issue is not that cleanup is missing entirely; it is that cleanup bypasses the abstraction that keeps observer state synchronized. Any direct write or delete to encrypted primary state needs a matching observer update, otherwise the observer can continue seeing values that the protocol has already cleared. Code references: `contracts/facets/liquidation/LiquidationFacetImpl.sol:202`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:204`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:503`, `contracts/facets/ViewFacet/ViewFacet.sol:153`, `contracts/facets/ViewFacet/ViewFacet.sol:174`, `contracts/facets/ViewFacet/ViewFacet.sol:353`, `contracts/facets/ViewFacet/ViewFacet.sol:363`.
- Impact: Observer views can return stale ciphertext after primary liquidation state is cleared.
- Attack path: After liquidation cleanup, observer tooling reads observer-specific views and receives old pending-balance or accumulator ciphertext.
- Recommendation: Use observer-aware encryption helpers for cleanup or explicitly clear observer storage.

### M-47: Plain liquidation detail fields stay stale after encrypted deficit and fee writes

- Severity: Medium
- Summary: Legacy plaintext liquidation detail fields can report zero while encrypted replacement values are nonzero.
- Description: The legacy `LiquidationDetail` struct still exposes plaintext `deficit` and `liquidationFee` fields through views, but the COTI fork writes the real values into encrypted replacement storage. The plaintext fields are initialized to zero and can remain stale, so consumers reading the old struct can see zero values while the actual encrypted liquidation deficit or fee is nonzero.

  This is a compatibility hazard caused by leaving obsolete plaintext fields in a public return type. External tooling that was built for the older Symmio data model may keep reading the old struct and make incorrect decisions because the meaningful values have moved elsewhere. Code references: `contracts/storages/AccountStorage.sol:29`, `contracts/storages/AccountStorage.sol:34`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:128`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:133`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:66`, `contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:71`.
- Impact: Dashboards, liquidator tooling, or indexers can read stale zero values from the legacy view.
- Attack path: A tool calls `getLiquidatedStateOfPartyA` and sees zero deficit or fee while encrypted state contains the actual amount.
- Recommendation: Remove stale plaintext fields from views or keep them synchronized with explicit public/private semantics.

### M-49: Public quote metadata leaks private trading intent

- Severity: Medium
- Summary: Numeric quote terms are encrypted, but quote routing and intent metadata remain public.
- Description: The quote path encrypts numeric terms such as price, quantity, and margin values, but leaves important intent and routing metadata as ordinary public fields. Symbol, side, order type, deadline, affiliate, and PartyB whitelist are visible in calldata, stored quote structs, and public views. Observers therefore still learn substantial trading intent even if the exact numeric terms are encrypted.

  This may be acceptable if the intended privacy model only protects numeric amounts. If the goal is broader trade-intent privacy, the current quote model leaks enough metadata to enable monitoring of symbols, direction, routing preferences, and targeted liquidity relationships. Code references: `contracts/storages/QuoteStorage.sol:69`, `contracts/storages/QuoteStorage.sol:70`, `contracts/facets/PartyA/PartyAFacet.sol:22`, `contracts/facets/PartyA/PartyAFacet.sol:64`, `contracts/facets/ViewFacet/ViewFacet.sol:456`, `contracts/facets/ViewFacet/ViewFacet.sol:531`.
- Impact: Observers can infer trading intent and targeted liquidity context even when price and quantity are encrypted.
- Attack path: An observer watches quote creation or views to learn symbol, side, order type, deadline, affiliate, and PartyB whitelist.
- Recommendation: Explicitly classify public metadata and encrypt, commit, or delay-disclose metadata that must remain private.

### M-50: Dust close requests can lock positions until PartyA cancels or the deadline expires

- Severity: Medium
- Summary: Close requests can be created with quantities that later close paths reject as too small.
- Description: Close-request creation validates that the requested close quantity is not greater than the open amount and that the remaining quote value is acceptable, but it does not run the same minimum proportional-release checks used by actual close execution. A dust close request can therefore move a position into `CLOSE_PENDING` even though both fill and force-close execution later reject it because proportional CVA/LF release rounds to zero.

  The bug is a validation mismatch between request creation and request execution. If a requested close quantity cannot ever be executed by the close path, it should be rejected before the quote state is changed to close-pending. Code references: `contracts/facets/PartyA/PartyAFacetImpl.sol:229`, `contracts/facets/PartyA/PartyAFacetImpl.sol:237`, `contracts/facets/PartyBPositionActions/PartyBPositionActionsFacetImpl.sol:110`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:147`, `contracts/facets/ForceActions/ForceActionsFacetImpl.sol:182`, `contracts/libraries/LibQuote.sol:189`.
- Impact: A position can remain stuck in `CLOSE_PENDING` until PartyA cancels or the deadline expires.
- Attack path: PartyA submits a dust close quantity that passes request validation but makes `lf * filledAmount / openAmount == 0` during execution.
- Recommendation: Run the same minimum proportional-close validation when creating the close request.

### L-01: Liquidation-fee splits silently discard rounding remainders

- Severity: Low
- Summary: Integer division floors liquidation reward shares and deletes the source balance.
- Description: Liquidation rewards are split using integer division, which floors each encrypted recipient share. The source liquidation-fee state is later deleted, so any remainder that does not divide evenly is not assigned to a recipient or a protocol dust bucket. Similar rounding can occur when remaining LF is split across PartyB liquidation recipients.

  The amounts are small, but the accounting should still specify where rounding dust goes. Silent deletion makes the final distributed total differ from the original fee amount and can accumulate over many liquidations. Code references: `contracts/facets/liquidation/LiquidationFacetImpl.sol:481`, `contracts/facets/liquidation/LiquidationFacetImpl.sol:485`, `contracts/libraries/LibLiquidation.sol:55`, `contracts/libraries/LibLiquidation.sol:57`.
- Impact: Small fee remainders are lost from reward accounting.
- Attack path: A liquidation fee or remaining LF value is not evenly divisible across recipients, leaving dust unassigned.
- Recommendation: Assign remainders deterministically or roll dust into protocol reserve accounting.

### L-03: `editAccountName` lacks account ownership validation

- Severity: Low
- Summary: Account-name editing mixes a global account index with the caller's account array.
- Description: The account-name edit function accepts an `accountAddress` argument, reads that account's global index, but writes into the caller's account array at the same index. It does not verify that the caller owns the supplied account address. As a result, the emitted event can identify one account while the actual storage write affects a different account belonging to the caller.

  This is not a direct funds issue, but account metadata is commonly consumed by frontends and indexers. Mismatched event and storage semantics can mislabel accounts or cause off-chain systems to attribute edits to the wrong address. Code references: `contracts/multiAccount/MultiAccount.sol:231`, `contracts/multiAccount/MultiAccount.sol:232`, `contracts/multiAccount/MultiAccount.sol:233`, `contracts/multiAccount/MultiAccount.sol:234`.
- Impact: Account metadata events can mislead off-chain indexers and users.
- Attack path: A user passes another owner's account address, causing the event to reference the victim account while storage mutation affects the caller's account at that index.
- Recommendation: Require ownership of `accountAddress` and emit the actual mutated account.

### L-04: Pagination views underflow when `start` exceeds the list length

- Severity: Low
- Summary: Pagination helpers can underflow instead of returning an empty page.
- Description: Pagination helpers attempt to clamp the requested page size, but the condition only checks whether `length < start + size`. If `start` itself is greater than `length`, the later `length - start` expression underflows under Solidity 0.8 checks instead of returning an empty page. This affects read-only helper behavior rather than core accounting.

  Pagination views should be robust for out-of-range starts because frontends and indexers often request pages optimistically. Returning an empty array is the expected behavior once the requested start is past the end of the list. Code references: `contracts/facets/ViewFacet/ViewFacet.sol:400`, `contracts/facets/ViewFacet/ViewFacet.sol:404`, `contracts/multiAccount/MultiAccount.sol:327`, `contracts/multiAccount/MultiAccount.sol:328`.
- Impact: Read-only views can revert for valid out-of-range pagination requests.
- Attack path: A frontend or indexer requests a page whose `start` is greater than the list length.
- Recommendation: Return an empty array when `start >= length` before subtracting.

### L-05: Next-ID views return the current last ID, not the next ID

- Severity: Low
- Summary: Next-ID helper views expose the current last ID instead of the next assigned ID.
- Description: Quote and bridge creation increment `lastId` before assigning the new object ID, so the next generated ID is `lastId + 1`. The helper views named as next-ID helpers return the current `lastId` instead, and the verifier helper compares against that same current value. The helper names therefore do not match the creation logic.

  This can break integrations that precompute or verify quote and bridge IDs before submitting a transaction. They will receive the previous/current ID from the helper while the next creation call assigns a different ID. Code references: `contracts/facets/ViewFacet/ViewFacet.sol:1141`, `contracts/facets/ViewFacet/ViewFacet.sol:1142`, `contracts/facets/PartyA/PartyAFacetImpl.sol:121`, `contracts/facets/Bridge/BridgeFacetImpl.sol:28`, `contracts/helpers/NextQuoteIDVerifier.sol:21`, `contracts/helpers/NextQuoteIDVerifier.sol:27`.
- Impact: Integrations can pre-sign or verify the wrong quote or bridge transaction ID.
- Attack path: An integration reads a next-ID helper before creation and uses the current last ID instead of the next assigned ID.
- Recommendation: Return `lastId + 1` or rename/document the helpers as current-last-id helpers.

### L-06: PartyB-filtered position views scan the wrong range and return sparse results

- Severity: Low
- Summary: PartyB-filtered view helpers treat quote IDs as dense zero-based indexes.
- Description: PartyB-filtered view helpers treat quote storage as a dense zero-based range and scan `quotes[i]` directly from `start` to `start + size`. Quote IDs are not handled as compact zero-based indexes, non-matching rows are left as default structs, and the scan is not cleanly clamped to the actual last quote ID. This produces sparse and potentially misleading view output.

  Consumers expect a PartyB-filtered view to return actual matching positions, not a fixed-size array containing empty default structs. The current behavior can make frontends and indexers miss positions or misinterpret empty entries as real data. Code references: `contracts/facets/ViewFacet/ViewFacet.sol:666`, `contracts/facets/ViewFacet/ViewFacet.sol:701`, `contracts/facets/ViewFacet/ViewFacet.sol:746`.
- Impact: Frontends and indexers can receive sparse arrays, miss positions, or scan empty quote IDs.
- Attack path: A client requests PartyB positions and receives default entries or misses valid positions outside the scanned ID window.
- Recommendation: Page over actual quote IDs and return compact arrays of matching results.

### L-08: Fee distributor can retain rounding dust while reporting the full amount claimed

- Severity: Low
- Summary: Fee distribution floors stakeholder transfers but emits the full claimed amount.
- Description: The fee distributor withdraws the full claimed amount from Symmio, then calculates each stakeholder payout independently with floored integer division. Even when stakeholder shares sum to 100%, the per-recipient floors can leave a remainder in the distributor contract. The event still reports the full amount as claimed, not the amount actually distributed.

  This is low severity because the remainder is rounding dust, but fee accounting should still be exact and transparent. A dust rollover or final-recipient remainder transfer would avoid silent accumulation and event/reporting mismatch. Code references: `contracts/SymmioFeeDistributor.sol:173`, `contracts/SymmioFeeDistributor.sol:177`, `contracts/SymmioFeeDistributor.sol:178`, `contracts/SymmioFeeDistributor.sol:181`.
- Impact: The event can overstate the amount actually distributed while collateral dust accumulates.
- Attack path: A claimed amount does not divide exactly across stakeholder shares, leaving the remainder in the distributor contract.
- Recommendation: Track dust explicitly or transfer the final remainder to a deterministic recipient.

### L-09: Multicall result arrays are returned empty for successful calls

- Severity: Low
- Summary: Multicall mutates memory copies of result entries instead of the returned array.
- Description: The Multicall helper allocates a return array, but each loop iteration copies a result slot into a local memory variable and mutates that copy. Because the updated `Result` is never assigned back to `returnData[i]`, successful subcall outputs are discarded before the function returns. The call execution and failure checks can still happen, which makes the bug easy to miss in simple execution tests.

  Any integration relying on returned data from `tryAggregate`, `aggregate3`, or `aggregate3Value` receives default result entries rather than the real subcall results. The fix is to write directly into the return array slot or assign the modified result back before continuing. Code references: `contracts/dev/multicall.sol:88`, `contracts/dev/multicall.sol:93`, `contracts/dev/multicall.sol:95`, `contracts/dev/multicall.sol:131`, `contracts/dev/multicall.sol:136`, `contracts/dev/multicall.sol:138`.
- Impact: Target calls execute, but returned result entries remain default `(false, "")`, breaking integrations that rely on batched return data.
- Attack path: A caller batches calls through the helper and receives empty/default result entries despite successful subcalls.
- Recommendation: Write directly to `returnData[i]` or assign the updated result back before returning.
