1:
`forceClosePosition` decrypts partyB's negative available balance to plaintext for the reserve vault math. `ForceActionsFacetImpl.sol:183 188`:
```
gtInt256 gtNegBalance = gtZero.sub(gtPartyBAvailableBalance);
int256 negBalance = MpcCore.decrypt(gtNegBalance);
uint256 available = uint256(negBalance);
accountLayout.reserveVault[quote.partyB] -= available;
```
this leaks the magnitude of partyB's deficit on every successful reserve covered force close. forceClosePosition is permissionless on any `CLOSE_PENDING` quote so anyone (a partyA, a competitor, a third party) can repeatedly probe a partyB by force closing tiny positions to map out their solvency margin over time. the original was plaintext anyway so there was no leak in symmio 8.4, but the fork encrypted the balance and then immediately decrypts it for the reserve subtraction, defeating the privacy.

2:
same function, the partyB liquidation sub branch at `ForceActionsFacetImpl.sol:215 217` decrypts both `quantityToClose` and `closePrice`:
```
uint256 quantityToClose = MpcCore.decrypt(gtQuantityToClose);
uint256 closePrice = MpcCore.decrypt(gtClosePrice);
int256 diff = (int256(quantityToClose) * (int256(closePrice) - int256(sig.currentPrice))) / 1e18;
```
both values were public in symmio 8.4 so the cleartext math was fine, but in the fork `quote.quantityToClose` and `quote.requestedClosePrice` are encrypted user state. `gtClosePrice` is derived from `gtRequestedClosePrice` plus a public penalty earlier in the same function, so decrypting it discloses partyA's private requested close price. fires only in the partyB liquidation sub branch but anyone can deliberately push a borderline solvent partyB into that branch by submitting a HighLowPriceSig that just barely tips them over.

3:
`LiquidationFacetImpl.sol:76 83` decrypts partyA's full financial state during `setSymbolsPrice`:
```
int256 availableBalance = MpcCore.decrypt(gtAvailableBalance2);
uint256 lf = MpcCore.decrypt(gtLf);
uint256 cva = MpcCore.decrypt(gtCva);
```
needed to pick the liquidation type but reveals the exact insolvency magnitude, locked liquidation fee, and cva of the liquidated party to whoever submits the tx.

same anti pattern repeats at three more sites the privacy refactor missed:
- `LibLiquidation.sol:41,49` , `liquidatePartyB` decrypts partyB's signed `availableBalance` magnitude and `lf` to choose between NORMAL and OVERDUE paths and compute liquidator share. fires on every partyB liquidation and hands the liquidator the exact insolvency magnitude.
- `DeferredLiquidationFacetImpl.sol:36,43` , `deferredLiquidatePartyA` decrypts partyA's `liquidationAvailableBalance` and `availableBalance` for the solvency check and the reimbursement on positive balance branch.
- `DeferredLiquidationFacetImpl.sol:89,95,96` , `deferredSetSymbolsPrice` is the deferred clone of `setSymbolsPrice` and decrypts the same balance/lf/cva triplet.

all four sites have the same root cause , destinations like `liquidationDetails.deficit` / `liquidationFee` / `partyAReimbursement` are plaintext storage so the encrypted comparisons get materialized to plaintext at the destination.

4:
every write to `settlementStates[partyA][quote.partyB].cva` / `.actualAmount` / `.expectedAmount` in `LiquidationFacetImpl.sol` (lines 206, 212, 217, 228, 234, 239, 248, 253, 261, 266) uses `offBoardCombined(value, partyAEncryptionAddress)`. symmio 8.4 had these as plain integers, both parties could read them. in the privacy fork, the user bound ciphertext is encrypted to partyA's key only. partyB cannot read their own pending settlement amount or cva refund off chain.

functional impact is currently nil because `settlePartyALiquidation` is commented out (one of the no ops from before), so the values are written but never used. but if/when that function is restored, partyB will see encrypted state they cannot decrypt to verify.

5:
`PartyAFacetImpl.sendQuote` collapses three distinct validation errors into one generic message. the original had `"LF is not enough"`, `"Quote value is low"`, and `"insufficient available balance"`. the fork combines all three into a single encrypted bool:
```
gtBool allValidationsPassed = lfSufficient.and(quoteSufficient).and(balanceSufficient);
require(MpcCore.decrypt(allValidationsPassed), "PartyAFacet: Validation failed");
```
i tested all three failure cases on coti testnet, they revert correctly but with no usable reason string. users have no way to tell which condition tripped.

6:
`LibSolvency.sol:139` does an mpc mux where both arms get evaluated, and the unselected arm underflows:
```
gtUint256 gtPriceDiff = MpcCore.mux(
    gtClosedPriceGteMarket,
    gtMarketPrice.sub(gtClosedPrice),
    gtClosedPrice.sub(gtMarketPrice)
);
```
mpc has no short circuit evaluation, so both subtractions run on the precompile. whichever one isnt selected does an unsigned underflow, the wrapped result is computed, then `mux` discards it. the actual return value is correct for now because mux picks the right arm, but the wasted computation does silently wrap on every call. fragile if the mux semantics ever change.

7:
the privacy fork overhauled the entire event layer and broke every off chain integration in the process. event names changed (`SendQuote` → `SendQuoteForPartyA` + `SendQuoteForPartyB`, `OpenPosition` → `OpenPositionForPartyA` + `OpenPositionForPartyB`, same for FillCloseRequest, ForceClosePosition, RequestToClosePosition). each name change produces a different keccak256 topic hash so any subgraph or monitoring dashboard filtering by the old topic matches zero events.

on top of that, event parameter types changed from `uint256` to `ctUint256` (which is a struct with two `ctUint128` fields), breaking the ABI encoding for any decoder expecting the old layout. and the backward compatibility duplicate events that symmio 8.4 had (old 2 arg `AllocatePartyA`, old 6 arg `ForceClosePosition`, etc) were all removed.

worst part: `ISymmio.sol:55 58` still declares the old event signatures:
```
event BalanceChangePartyA(address indexed partyA, uint256 amount, BalanceChangeType _type);
event BalanceChangePartyB(address indexed partyB, address indexed partyA, uint256 amount, BalanceChangeType _type);
```
but `SharedEvents.sol:25 27` (what actually gets emitted) uses `ctUint256 amount`. different ABI, different topic hash. any tool using ISymmio's ABI to filter these events will never match the actual emissions.

the protocol's off chain layer is blind without a full ABI rebuild. for a perp DEX where 100% of user interaction happens via off chain UIs reading events, this means the UI cant display portfolio data, trade history, or balance updates.

8:
`setEncryptionAddress` is implemented in `AccountFacet.sol:189` but is not declared in `IAccountFacet.sol`. since `ISymmio` inherits `IAccountFacet`, the canonical interface for the diamond also lacks this function. any external caller (frontend, multisig, other contract) that uses the interface to discover or call diamond functions wont see `setEncryptionAddress` exists. theyll have to hardcode the selector or use a raw call.
