1:
in lockAndOpenQuote (PartyBGroupActionsFacet.sol around line 43) you used LibAccount.getUserEncryptionAddress and uses it as the partyA encryption address for the SendQuoteForPartyA event. but onlyPartyB modifier means msg.sender is partyB. so partyA's event is encrypted to partyB's key. partyA can't read their own data, partyB sees what should've been private. i guess maybe you can use getUserEncryptionAddress(newQuote.partyA)

2:
same issue vector but in settlement. LibSettlement.sol lines 126 128 and 137 139 do offBoardToUser(gtAmount, partyAEncryptionAddress) for the partyB amount in BalanceChangePartyB. wrong direction. partyB's value encrypted to partyA's key. and its in both branches of the if/else (positive and negative settlement amount), so whoever fixes it needs to touch both spots.

3:
LibSettlement.sol:65,81 straight up calls MpcCore.decrypt(gtOpenedPrice) and decrypt(gtQuoteOpenAmount) to plaintext, just so the function can do if (openedPrice > data.currentPrice) and the settlement math in cleartext. the whole point of the privacy fork is to keep these encrypted. right? the same comparison can be done with MpcCore.mux , getAvailableBalanceAfterClosePosition in LibSolvency already does it that way. fires on every settleUpnl, so every cross party settlement is leaking entry price and position size.

4:
lockAndOpenQuote again, but the function signature itself (lines 23 29). it takes uint256 filledAmount, uint256 openedPrice as plaintext params and just wraps them with MpcCore.setPublic256 before calling the lib. the standalone openPosition was updated to take encrypted inputs (isnt that the whole point of the fork?) but this batch path got left behind. anyone using this entry point leaks fill amount and opened price in calldata.

5:
MultiAccount.addAccount (line 216 222) deploys a new subaccount and never calls setEncryptionAddress on it. so when the subaccount later interacts with encrypted state, getUserEncryptionAddress(subAccount) falls back to the subaccount's own address : a contract with no off chain key material. nobody can decrypt the data. the EOA owner is locked out.
depositAndAllocateForAccount makes this concrete: it deposits and immediately calls allocate(uint256) through innerCall, writing the user's first allocated balance ciphertext to that undecryptable address. permanently stuck. test suite hides this by setting a global trustedEncryptionAddress in the fixture , production users have no such safety net. if that trusted address is ever unset or removed, every existing subaccount becomes unrecoverable.

6:
SettlementFacet.settleUpnl literally has a loop that decrypts every partyB allocated balance to plaintext and emits them in the SettleUpnl event. lines 33 45. the original event signature was uint256[] because balances were plaintext in old symmio. when the fork made partyBAllocatedBalances encrypted, you kept the event signature and added a decrypt loop to populate it. result: every settlement publicly publishes the post settlement balance of every involved partyB.
combined with no muon check issue, anyone can call settleUpnl with a fabricated sig and read those balances on demand. its a free oracle. and there's a second occurrence at ForceActionsFacet.sol:108 122 , the non liquidated branch of forceClosePosition does the exact same thing, decrypts gtPartyBAllocatedBalance and emits it in SettleUpnl. and forceClosePosition is permissionless on any CLOSE_PENDING quote, so no sig needed at all. 

7:
the trading fee gets decrypted to plaintext on basically every protocol entry point. PartyAFacetImpl.sol:160 (sendQuote), PartyAFacetImpl.sol:186 (requestToCancelQuote), LibPartyBPositionsActions.sol:69 (openPosition), LiquidationFacetImpl.sol:122 (pending liquidation cleanup). same shape every time:

uint256 fee = MpcCore.decrypt(gtTradingFee);
gtUint256 gtFeeAmount = MpcCore.setPublic256(fee);

the fee is quantity * price * feeRate / 1e36 and feeRate is public per symbol. so once you see the decrypted fee value, you have quantity * price directly. one of those two is usually known or boundable from market data so the other becomes recoverable too. quantity and entry price were supposed to be the encrypted bits , this leaks them on every sendQuote, every cancel, every openPosition, every liquidation cleanup. probably the most pervasive privacy leak in the whole fork. fix is to keep the fee bucket encrypted on the feeCollector side, or do a deferred reveal pattern, basically anything that doesnt decrypt at the call site.

8:
LibQuote.sol:142 144 decrypts the price comparison on every closeQuote:

bool isCurrentGreater = MpcCore.decrypt(gtCurrentPrice.gt(gtOpenedPrice));
bool isLong = quote.positionType == PositionType.LONG;
hasMadeProfit = isLong ? isCurrentGreater : !isCurrentGreater;

positionType is public state. so once you decrypt the price comparison and combine it with positionType you have whether the position was profitable. fires on every close (not just settlement, every single close goes through getValueOfQuoteForPartyA). pnl direction leak on every trade exit. same pattern is also in LibSolvency.sol:56 for the open path. fix is to keep the comparison encrypted and use mux to pick the pnl branch instead of branching on a decrypted bool.