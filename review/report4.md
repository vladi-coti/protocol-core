1:
because settlePartyALiquidation and resolveLiquidationDispute are commented out (from the earlier no ops report), partyA liquidation has no terminal state. once a partyA gets liquidated through steps 1 to 4 (liquidatePartyA → setSymbolsPrice → liquidatePositionsPartyA → liquidatePendingPositionsPartyA), they're stuck forever:

liquidationStatus[partyA] stays true permanently. thats the only flag that gets checked by notLiquidatedPartyA modifier, which blocks deallocate, sendQuote, requestToClosePosition, internalTransfer, basically everything. and liquidationStatus[partyA] = false only exists at LiquidationFacetImpl.sol:450 inside the settlePartyALiquidation tail block, which is dead code.

so after a liquidation: partyA's allocatedBalances are frozen, lockedBalances never get zeroed (margin locked against positions that no longer exist), partyAReimbursement (trading fee refunds from pending quote cleanup) is permanently captured with no payout path, the liquidation fee that liquidators earned is set in liquidationDetails but never distributed to them, and partyANonces is never bumped so every muon sig over the pre liquidation nonce stays in the replay window forever.

partyA cant recover, cant re enter trading, cant even be re liquidated (the notLiquidatedPartyA modifier on liquidatePartyA itself prevents re entry). the protocol accumulates ghost balances on every liquidation. and no rational liquidator will operate because they burn gas and never get paid.

i ran this on coti testnet: liquidated partyA, called settlePartyALiquidation (no op), tried to deallocate, still reverted. permanently trapped.

2:
fillCloseRequest and openPosition have a revert oracle that lets any partyB recover partyA's encrypted requestedClosePrice, requestedOpenPrice, quantity, and quantityToClose via binary search.

the pattern looks like this at LibPartyBPositionsActions.sol:24 28:

gtUint256 gtRequestedClosePrice = LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext);
gtBool gtPriceValid = quote.positionType == PositionType.LONG
    ? gtClosedPrice.ge(gtRequestedClosePrice)
    : gtClosedPrice.le(gtRequestedClosePrice);
require(MpcCore.decrypt(gtPriceValid), "PartyBFacet: Closed price isn't valid");

partyB controls gtClosedPrice. the require decrypts a boolean thats a comparison against partyA's encrypted requestedClosePrice. success means partyB's probe was on the right side of the threshold, revert means it wasnt. thats a one bit oracle.

partyB doesnt even need to submit on chain transactions. they simulate fillCloseRequest via eth_call against their own rpc node, observe success/revert, adjust the probe value, repeat. ~25 simulations to binary search any 18 decimal price to one wei precision. zero gas cost, zero on chain footprint. by the time partyB actually fills, they already know partyA's exact desired close price.

same pattern at:





LibPartyBPositionsActions.sol:29 33 recovers quantityToClose



LibPartyBPositionsActions.sol:63 recovers quantity for LIMIT orders



LibPartyBPositionsActions.sol:74 recovers requestedOpenPrice



LibPartyBPositionsActions.sol:189 recovers the leverage ratio (quantity * openedPrice / totalForPartyA)

combined: a market maker partyB can recover partyA's complete strategy (price, quantity, position size) on any quote before committing to fill it. the privacy fork encrypted these fields specifically to prevent this. the revert oracle defeats it entirely.

this isnt fixable with a one liner. decrypting a boolean into a require where the comparison input is caller controlled is inherently a side channel. needs a structural redesign like commit/reveal fills or moving the validation to the muon oracle.

3:
PartyAFacetImpl.requestToClosePosition at lines 225 226:

gtBool isFullClose = gtQuoteOpenAmount.eq(gtQuantityToClose);
if (!MpcCore.decrypt(isFullClose)) {

this decrypts whether partyA is closing their entire remaining position vs a partial close. the boolean is visible on chain to anyone watching the tx trace. full close vs partial close is a high information signal in trading (full close = exiting the position, often profit taking or stop loss; partial close = scaling out or hedging adjustment). market makers and arbs trade on this signal.

worse: combined with knowledge of the original quote quantity (recoverable through the revert oracle above, or through partial close events), isFullClose = true reveals quantityToClose == quote.quantity - quote.closedAmount exactly, which leaks the remaining position size.

theres also a gas side channel. the two branches do different amounts of work (the partial close branch runs a remaining value check that the full close branch skips), so gas usage differs and an observer can infer which branch was taken without even looking at the decrypt result.

same pattern at LibQuote.closeQuote:222 (isFinalClose decrypt) and LibQuote.closeQuote:298 (isFullyClosed decrypt) on the actual fill path.

4:
AccountFacetImpl.setEncryptionAddress re encrypts the partyA side state but not the partyB side. lines 211 to 244 iterate allocatedBalances[user], lockedBalances[user], pendingLockedBalances[user], and every quote where q.partyA == user. it doesnt touch partyBAllocatedBalances[user][*], partyBLockedBalances[user][*], partyBPendingLockedBalances[user][*], or settlementStates[*][user]. so when a partyB rotates their key, every per partyA balance and locked value they hold becomes unreadable to them. partyAs they have positions with can still read it (the network ciphertext is still valid for chain ops) but the partyB themselves are locked out off chain.

5:
AccountFacetImpl.internalTransfer (line 124) doesnt initialize the recipient's encrypted state before reading or writing it. allocate calls LibAccount.initializePartyA(msg.sender) first, internalTransfer doesnt do the equivalent for the target. transfer to a fresh address and the recipient's lockedBalances slot is still all zero ciphertext. next time something does an onBoard (not safeOnboard) on those slots it reads garbage. i tested this on coti testnet and internalTransfer to a fresh address reverted.

6:
AccountFacetImpl.setEncryptionAddress lines 207 to 209:

if(accountLayout.trustedEncryptionAddress != address(0)) {
    return;
}

when trustedEncryptionAddress is set, the function records the new per user address and returns early without re encrypting anything. that's by design for the trusted mode (the new address is irrelevant while trusted is set), but if the trusted address is later removed, every user's data is still encrypted to the trusted one and the per user mapping points to whatever they last set, which never matched the actual ciphertexts. there's no recovery path because the function will refuse to re run with the same address it already recorded.

7:
the LockedValuesOps.mux wrapper at LibLockedValues.sol:291 303 has parameter names that lie about what it does:

function mux(
    gtBool condition,
    GarbledLockedValues memory trueValue,
    GarbledLockedValues memory falseValue
) internal returns (GarbledLockedValues memory) {
    return GarbledLockedValues({
        cva: MpcCore.mux(condition, falseValue.cva, trueValue.cva),
        ...
    });
}

MpcCore.mux(cond, a, b) returns b when cond is true and a when false , the opposite of a normal ternary. the wrapper compensates by passing (condition, falseValue, trueValue) internally so the named parameters end up correct from the caller's perspective. existing call sites that use the wrapper are correct but anyone copy pasting the wrapper's body or trusting the parameter names will get the inversion wrong.

8:
LibAccount.initializePartyB lines 269 to 273 couples three independent storage slots behind one check:

if (lockedBalances.isUninitialized()) {
    lockedBalances.initializeToZeros(...);
    pendingLockedBalances.initializeToZeros(...);
    initializeToZeros(settlementState, ...);
}

if the three ever drift out of sync (one gets zeroed by some other path while the other two stay populated, etc) the missing ones never recover because the gate only checks lockedBalances.

9:
LibMuon.sol:14 17 has a hardcoded fallback chain id commented out:

function getChainId() internal view returns (uint256 id) {
    id = block.chainid;
    // FIXME: temporary until chainid is fixed
    // id = 15151515;
}

not broken right now but the FIXME suggests block.chainid was unreliable somewhere during development. worth understanding why before deploying.

10:
ViewFacet.sol , most of the read functions used to return plain uint256, the privacy fork changed them to return ctUint256 / utUint256 to expose the encrypted state. silently breaks every existing integration that used to read plain values. not a security issue but worth flagging because every off chain consumer (subgraph, frontend, monitoring, third party integrations) will need to be updated to decrypt these fields.

11:
AccountFacetImpl.setEncryptionAddress has two more issues beyond the partyB side gap from earlier in this list. first, the wrapper at AccountFacet.sol:189 195 has zero modifiers , no whenNotAccountingPaused, no notSuspended, no notLiquidatedPartyA. every other state mutating function in AccountFacet carries at least whenNotAccountingPaused and most carry notSuspended or notLiquidatedPartyA. a user under emergency pause, suspended, or mid liquidation can still rotate their key.

second, the storage write at AccountFacetImpl.sol:205 happens BEFORE the re encryption loop. if the loop reverts (out of gas, proportional to quoteIdsOf[user].length), the early userEncryptionAddress[user] = newEncryptionAddress write persists. the mapping now points to the NEW address but storage still holds ciphertexts encrypted to the OLD one. the user's natural retry (setEncryptionAddress(NEW) again) is blocked by the unchanged address require at line 203, which now sees effectiveCurrent == NEW. only recovery is to rotate to a different address first then back, two transactions and four trips through the gas heavy loop.