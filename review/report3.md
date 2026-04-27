1:
AccountFacetImpl.transferAllocation (lines 91 122) reads partyBAllocatedBalances[msg.sender][origin] and partyBAllocatedBalances[msg.sender][recipient] BEFORE writing either. when origin == recipient both reads return the same X, then both writes hit the same slot:

gtNewOriginBalance     = X - amount       (line 116)
gtRecipientBalance     = X                 (line 117, fresh read of the same slot)
gtNewRecipientBalance  = X + amount       (line 118)
storage[slot] = X - amount                 (line 120)
storage[slot] = X + amount                 (line 121, OVERWRITES line 120)

balance went from X to X+amount. you minted amount out of thin air. and there's no require(origin != recipient) anywhere in the function.

symmio 8.4 uses partyBAllocatedBalances[msg.sender][origin] -= amount; ...[recipient] += amount. compound assignment is sequential SLOAD/SSTORE so the second line reads the value left by the first one and the math nets to zero. the fork lost that property by splitting the read and the write into separate steps for the encrypted types.

exploit is one line. partyB seeds 100 collateral via allocateForPartyB, calls transferAllocation(100, partyA, partyA, sig), balance is 200. iterate. ~60 calls and the balance is 2^60 * 100. then deallocateForPartyB(huge_amount, ...) and withdraw(...). drain. i actually ran this on coti testnet, balance went from 100 to 200 in a single call.

even with the muon check fixed it still works because the sig binds (msg.sender, origin) and partyB legitimately holds X against partyA. recipient address isnt in the sig hash.

2:
this one is a class level finding. the COTI mpc library exposes two arithmetic api families on every encrypted integer type: plain add / sub / mul which wrap mod 2^256 and DO NOT revert on overflow, and checkedAdd / checkedSub / checkedMul which take an overflow bit out of the precompile and route it through checkRes256 → checkOverflow → require(decrypt(notBit) == true, "overflow error"). the library author even left a comment at MpcCore.sol:11 explaining that the checked variants are the ones that revert.

the privacy fork uses zero of the checked variants. i grepped the whole contracts/ tree and there isnt a single checkedAdd / checkedSub / checkedMul / checkedDiv call. meanwhile there are hundreds of plain .add(, .sub(, .mul( calls scattered across AccountFacetImpl.sol, LibLiquidation.sol, LibSettlement.sol, LibQuote.sol, LibAccount.sol, LiquidationFacetImpl.sol, PartyAFacetImpl.sol, LibPartyBPositionsActions.sol, LibSolvency.sol, LockedValuesOps, etc.

the symmio 8.4 code these calls replaced was solidity 0.8, where every + / - / * reverts on overflow. the privacy refactor mechanically translated + → .add(, - → .sub(, * → .mul( and silently dropped the revert semantics across the whole protocol. every accounting flow that used to be protected by 0.8 is now wrap silent.

the next three items in this list (the settleUpnl underflow, the liquidatePartyB underflow, the sendQuote balance check bypass) are concrete instances i actually traced. they are not exhaustive. there are also probably broken sites i havent had time to attack yet:





LibAccount.partyAAvailableForQuote / partyBAvailableForQuote line 73 to 91 do allocated - cvaLfPending - max(-upnl, mm) as multiple encrypted subs. when the user's locked balances exceed allocated (a NORMAL state mid position), the result wraps and then gets .toSigned()'d into the signed comparison. one wrap here corrupts every downstream solvency check across the protocol. potentially the worst site of all but i havent built an exploit yet.



LibQuote.closeQuote around line 285 does avgClosedPrice * closedAmount + filledAmount * closedPrice then divides. two unbounded encrypted muls.



LibPartyBPositionsActions.openPosition lines 64 and 67 do gtFilledAmount * gtRequestedOpenPrice * gtTradingFeeRate before dividing. three muls. for a large position on a high priced symbol the intermediate can blow past 2^256.



every site that computes totalForPartyA or totalForPartyB via three chained .add(.

the COTI library ships checkedAdd / checkedSub / checkedMul variants for exactly this purpose. they should be used everywhere arithmetic isnt provably bounded.

i deployed a small probe contract to coti testnet to confirm: sub(30, 100) returned 2^256 - 70, add(MAX-100, 200) returned 99, mul(2^128, 2^128) returned 0, and checkedSub(30, 100) reverted. so the next three items rely on actual on chain wrap behavior, not just docs.

3:
LibSettlement.settleUpnl does an unguarded encrypted sub at lines 122 and 159:

gtUint256 gtNewBalance = gtPartyBBalance.sub(gtAmount);          // line 122
...
gtUint256 gtNewBalance = gtPartyABalance.sub(gtAmount);          // line 159

encrypted gtUint256.sub runs in the COTI mpc precompile and wraps mod 2^256. it does NOT revert on underflow. when settlementAmount > partyBBalance (line 122) or |totalSettlementAmount| > partyABalance (line 159), the sub silently produces ~2^256 - delta and writes it to storage. the loser of the settlement now has ~2^256 allocated.

symmio 8.4 at lines 102 and 114 uses -= uint256(...) which is solidity 0.8 and reverts on underflow. you mechanically translated -= into gtUint256.sub without realising the revert was the safety net.

with the muon check disabled, any caller can fabricate a sig with controlled upnl and updatedPrices such that the per quote settlement amount exceeds the loser's collateral. it also happens naturally on any leveraged position with adverse price movement. then deallocateForPartyB (or deallocate for partyA) extracts the wrapped balance.

4:
same shape of bug in LibLiquidation.liquidatePartyB, line 97:

gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(...partyBAllocatedBalances[partyB][partyA].ciphertext);
gtUint256 gtRemainingLf = MpcCore.setPublic256(remainingLf);
gtUint256 gtValue = gtPartyBBalance.sub(gtRemainingLf);
gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(...allocatedBalances[partyA].ciphertext);
gtUint256 gtNewPartyABalance = gtPartyABalance.add(gtValue);

when remainingLf > partyBBalance the encrypted sub wraps and gtValue becomes ~2^256 - delta. that wrapped value gets added to partyA's allocated balance, so partyA ends up with ~2^256.

liquidation enters the NORMAL branch when |availableBalance| < lf. if you do the algebra the underflow condition reduces to upnl > cva for partyB. that's reachable any time a profitable partyB market maker has unrealized gains larger than their cva and the rest of their state pushes availableBalance below zero (lots of lf, not much allocated).

symmio 8.4 at line 72 was uint256 value = partyBAllocatedBalances[partyB][partyA] - remainingLf which reverts on underflow.

extracting from this one is messier than the previous two because the wrapped partyA balance interacts badly with downstream .toSigned() checks (sign bit flips), but the accounting invariants are wrecked either way and the wrapped balance is still usable through sendQuote with crafted locked values.

5:
PartyAFacetImpl.sendQuote line 95 has a balance check that's bypassable:

gtUint256 totalRequired = gtTotalForPartyA.add(gtTradingFee);              // line 91
gtInt256 gtAvailableBalance = LibAccount.partyAAvailableForQuote(upnlSig.upnl, msg.sender);
gtBool balanceSufficient = totalRequired.toSigned().le(gtAvailableBalance);  // line 95

totalRequired is a gtUint256 and .toSigned() is a pure bit reinterpret, its literally gtInt256.wrap(gtUint256.unwrap(a)) in MpcSignedInt.fromUint256. so any value with the high bit set becomes negative in signed semantics. negative <= any positive available balance is always true. so a partyA who supplies encrypted cva + partyAmm + lf summing to >= 2^255 bypasses the balance check entirely.

inputs come straight from the user (cva, lf, partyAmm, partyBmm are all it* user supplied), and validateCiphertext only checks the user's signature on the ciphertext, not the underlying plaintext range. so partyA can submit cva = 2^254, partyAmm = 2^254, lf = 1e16, quantity = 1, price = 1 and the validation passes. then the quote gets created and pendingLockedBalances[partyA] gets incremented by the wrapped values.

original is safe because solidity 0.8 reverts on overflow in cva + partyAmm + lf. the encrypted types in the fork silently wrap mod 2^256.

most direct impact is that partyA can brick their own account (corrupted pendingLockedBalances make their solvency math wrap, recoverable through requestToCancelQuote which reverses the addition). but the same class affects every other gt*.add() and gt*.sub() in the fork that isnt bounds checked, which is most of them.

6:
ControlFacet.setTrustedEncryptionAddress (line 527) is literally 4 lines and does nothing beyond flipping the storage slot:

function setTrustedEncryptionAddress(address trustedEncryptionAddress) external onlyRole(...) {
    AccountStorage.Layout storage accountLayout = AccountStorage.layout();
    address oldTrustedEncryptionAddress = accountLayout.trustedEncryptionAddress;
    accountLayout.trustedEncryptionAddress = trustedEncryptionAddress;
    emit SetTrustedEncryptionAddress(oldTrustedEncryptionAddress, trustedEncryptionAddress);
}

no re encryption loop, no iteration, no migration. when this gets called, every existing ciphertext in the protocol is still encrypted to the OLD address but getUserEncryptionAddress now returns the NEW one. all three transitions break:

going from addr(0) to addr1 (initial setup): users' pre existing per user data is still readable by the user, but every NEW ciphertext from now on is only readable by addr1. user accounts split between two key holders forever.

going from addr1 to addr2 (rotation): all historical ciphertexts are bound to addr1 forever. addr1 retains read access to every user's pre rotation state. addr2 only sees post rotation.

going from addr1 back to addr(0) (disable): existing data unreadable to anyone except addr1. per user setEncryptionAddress only re encrypts data the user OWNS, not their counterparty side state. so the partyB side stuff (partyBAllocatedBalances[user][*], partyBLockedBalances[user][*], settlementStates[*][user].cva/actualAmount/expectedAmount) is permanently lost because those mappings arent iterable.

the other side of this: while trusted is set, the trusted address holder can decrypt EVERYTHING. allocated balances of every user, every quote's price/quantity/locked values, every settlement state. the privacy claim degrades from "no third party reads your data" to "exactly one third party reads everything." not the model users sign up for.

worth flagging: the test fixture sets trustedEncryptionAddress = liquidator.address. so every test runs in trusted mode AND the liquidator is the universal decryptor. probably done for convenience but it means every test path masks several other bugs in the same area (the addAccount one that skips setEncryptionAddress, and the per user re encryption ones). and if production replicates this setup, the liquidator can run a market making bot that reads every partyA's submitted price, quantity, and locked margins before the quote is even locked.

7:
four normal flow functions decrypt the FULL 256 bit balance magnitude when they only need a boolean. each fires on every legitimate use of the protocol.

AccountFacetImpl.deallocate line 80:

int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
require(availableBalance >= 0, "...");
require(uint256(availableBalance) >= amount, "...");

leaks partyA's exact net available balance on every deallocate.

AccountFacetImpl.deallocateForPartyB line 171: same pattern, leaks partyB's exact per partyA available balance on every deallocateForPartyB.

AccountFacetImpl.transferAllocation line 105: same pattern, leaks partyB's per origin available balance on every transferAllocation.

PartyBQuoteActionsFacetImpl.lockQuote lines 28 and 34: TWO leaks in one call. line 28 decrypts partyB's full available balance against partyA, then line 34 decrypts totalForPartyB = cva + lf + partyBmm of the quote being locked, which is partyA's private quote risk profile.

the lockQuote one is the worst because it leaks BOTH counterparties' private state on EVERY market maker quote lock action, which is the most frequent op in any active perpetuals protocol. and combined with the disabled muon check, any address (not just real partyBs) can call lockQuote to probe partyA quotes without needing authorization. its a free oracle.

symmio 8.4 has no privacy claim so this was fine there. the fork added the privacy promise but didnt migrate these comparisons to encrypted compare then decrypt the bool.

8:
SendQuoteForPartyA and SendQuoteForPartyB events have corrupted identity fields at five emit sites. the fork split the original SendQuote into per recipient flavors with a new partyB field that's supposed to identify which whitelist entry the event corresponds to. none of the five emit sites populate it correctly and four of them also corrupt the partyA field.

bug 1: the partyB field gets getUserEncryptionAddress(...) instead of the user address. with trustedEncryptionAddress set, every iteration of the loop emits the same trusted address as the partyB field. indexers see N copies of the same event all attributed to the trusted gateway with no way to recover which whitelist entry each one was for.

sites: PartyAFacet.sol:87, PartyBPositionActionsFacet.sol:58, PartyBGroupActionsFacet.sol:81.

bug 2: the partyA field gets msg.sender in functions that are partyB callable. PartyBPositionActionsFacet.openPosition has onlyPartyBOfQuote so msg.sender IS partyB. the partial fill child branch emits SendQuoteForPartyA(msg.sender, ...) and SendQuoteForPartyB(msg.sender, ...) which both put partyB in the partyA slot.

sites: PartyBPositionActionsFacet.sol:55,58, PartyBGroupActionsFacet.sol:55,79.

symmio 8.4 at PartyBPositionActionsFacet.sol:35 and PartyBGroupActionsFacet.sol:42 uses newQuote.partyA.

every quote ends up with at least one corrupted identity field in its SendQuoteForPartyB event. every partial fill child quote has both fields corrupted in BOTH events. off chain indexers, the official subgraph, monitoring, any UI that filters "quotes addressed to me" by partyB == myAddress see nothing.

9:
liquidatePositionsPartyA at LiquidationFacetImpl.sol:289 305 decrypts both the per pair settlement amount AND partyB's full allocated balance on the last quote of every (partyA, partyB) pair:

if (quoteLayout.partyBPositionsCount[quote.partyB][partyA] == 0) {
    gtInt256 gtSettleAmount = MpcCore.onBoard(...expectedAmount.ciphertext);
    int256 settleAmount = MpcCore.decrypt(gtSettleAmount);                   // line 292
    if (settleAmount < 0) { ... } else {
        gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(...partyBAllocatedBalances[quote.partyB][partyA].ciphertext);
        uint256 partyBBalance = MpcCore.decrypt(gtPartyBBalance);            // line 298
        ...
    }
}

both settlementStates[partyA][partyB].expectedAmount and partyBAllocatedBalances[partyB][partyA] are encrypted, but this function decrypts both because liquidationDetails[partyA].partyAAccumulatedUpnl is plaintext int256 (see AccountStorage.sol:32) and was never migrated. the destination accumulator forces the source to be revealed.

per call you leak (1) the aggregate signed pnl of all of partyA's positions vs that specific partyB at liquidation time and (2) partyB's full allocated balance for that partyA. trigger is anyone with LIQUIDATOR_ROLE calling liquidatePositionsPartyA.

10:
LiquidationFacetImpl.sol has 10 sites that read settlementStates[partyA][partyB].actualAmount.ciphertext and .expectedAmount.ciphertext using raw MpcCore.onBoard instead of a safe wrapper. lines 210, 215, 232, 237, 246, 251, 259, 264, 291, 359. every other field on the same struct (like cva) uses LockedValuesOps.safeOnboard. that wrapper exists because the precompile doesnt handle all zero ciphertext gracefully:

function safeOnboard(ctUint256 memory value) internal returns (gtUint256) {
    if (ctUint128.unwrap(value.ciphertextHigh) == 0 && ctUint128.unwrap(value.ciphertextLow) == 0) {
        return MpcCore.setPublic256(uint256(0));
    }
    return MpcCore.onBoard(value);
}

theres no equivalent helper for ctInt256, so the int variant goes straight to raw MpcCore.onBoard. you wrote the uint helper because the issue was real, but forgot to do the int side.

settlementStates[partyA][partyB] is initialized only via LibAccount.initializePartyB, which gets called from exactly two places: allocateForPartyB and transferAllocation. lockQuote has its own _ensureInitializedPartyBLockedBalances that initializes partyBLockedBalances and partyBPendingLockedBalances but NOT settlementStates. so any partyB that reaches a position liquidation step without going through allocateForPartyB first has zero ciphertext in their settlement state. next raw MpcCore.onBoard either reverts (DoSes the liquidation) or returns garbage (corrupts the settlement amount).

normally lockQuote requires positive available balance which forces allocateForPartyB first, so the bug is latent. but with the muon check disabled any partyB can pass an attacker controlled upnl to bypass that and reach the buggy path.

11:
two more in lockAndOpenQuote (PartyBGroupActionsFacet.sol). already sent the wrong key offboard and the plaintext params from this function before. these are different bugs in the same function.

bug A: lines 54 and 78 emit quoteId (the parent's id from the function input) instead of newQuote.id for both SendQuoteForPartyA and SendQuoteForPartyB. symmio 8.4 at line 43 of the same file uses newQuote.id. on chain state is fine but every indexer reading these events will attribute the new child's data to the parent's id and the actual child quote will be invisible.

bug B: this function doesnt emit ANY open position event. symmio 8.4 at line 37 of PartyBGroupActionsFacet.sol does emit OpenPosition(quoteId, quote.partyA, quote.partyB, filledAmount, openedPrice) right after the openPosition call. the privacy fork replaced the unified OpenPosition with split encrypted OpenPositionForPartyA / OpenPositionForPartyB, wired them into the standalone PartyBPositionActionsFacet.openPosition (lines 43 44), and forgot to wire them into lockAndOpenQuote. so positions opened through this batch entry point are completely invisible to anything watching open position events.

between these two and the previous ones, every event emitted by lockAndOpenQuote ends up with at least one wrong field (wrong key, wrong quoteId, missing identity, or just missing). looks like the function was refactored without revisiting the events.