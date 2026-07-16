// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/muon/LibMuonPartyB.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibPartyBQuoteActions.sol";
import "../../libraries/LibEncryption.sol";
import "../../libraries/LibOnChainUpnl.sol";

library PartyBQuoteActionsFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function lockQuote(uint256 quoteId, SingleUpnlSig memory upnlSig) internal {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		LibMuonPartyB.verifyPartyBUpnl(upnlSig, msg.sender, quote.partyA);
		
		LibAccount.initializePartyB(msg.sender, quote.partyA);
		
		// Only decrypt the final predicates, not the underlying balance magnitudes.
		gtInt256 gtComputedUpnl = LibOnChainUpnl.partyBUpnlFromQuotePrices(msg.sender, quote.partyA, LibOnChainUpnl.priceSigFromSingle(upnlSig));
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableForQuote(gtComputedUpnl, msg.sender, quote.partyA);
		gtBool gtAvailableBalanceNonNegative = LibAccount.isNonNegative(gtAvailableBalance);
		require(MpcCore.decrypt(gtAvailableBalanceNonNegative), "PartyBFacet: Available balance is lower than zero");
		
		// Keep the sufficiency check in the encrypted domain.
		GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
		gtUint256 gtTotalForPartyB = gtLockedValues.totalForPartyB();
		gtBool gtAvailableBalanceSufficient = LibAccount.isAtLeastAmount(gtAvailableBalance, gtTotalForPartyB);
		require(MpcCore.decrypt(gtAvailableBalanceSufficient), "PartyBFacet: insufficient available balance");
		
		LibPartyBQuoteActions.lockQuote(quoteId);
	}

	function unlockQuote(uint256 quoteId) internal returns (QuoteStatus) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

		Quote storage quote = quoteLayout.quotes[quoteId];
		require(quote.quoteStatus == QuoteStatus.LOCKED, "PartyBFacet: Invalid state");
		if (block.timestamp > quote.deadline) {
			QuoteStatus result = LibQuote.expireQuote(quoteId);
			return result;
		} else {
			quote.statusModifyTimestamp = block.timestamp;
			quote.quoteStatus = QuoteStatus.PENDING;
			LibEncryption.storePartyBPendingLockedBalance(
				accountLayout,
				quote.partyB,
				quote.partyA,
				accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote)
			);
			LibQuote.removeFromPartyBPendingQuotes(quote);
			quote.partyB = address(0);
			return QuoteStatus.PENDING;
		}
	}

	function acceptCancelRequest(uint256 quoteId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(quote.quoteStatus == QuoteStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		quote.statusModifyTimestamp = block.timestamp;
		quote.quoteStatus = QuoteStatus.CANCELED;
		LibEncryption.storePartyAPendingLockedBalance(accountLayout, quote.partyA, accountLayout.pendingLockedBalances[quote.partyA].subQuoteGarbled(quote));
		LibEncryption.storePartyBPendingLockedBalance(
			accountLayout,
			quote.partyB,
			quote.partyA,
			accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote)
		);

		// send trading Fee back to partyA
		gtUint256 gtFeeAmount = LibQuote.getTradingFee(quoteId);
		
		// Update allocated balance with encrypted operations
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
		gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtFeeAmount);
		LibEncryption.storePartyAAllocatedBalance(accountLayout, quote.partyA, gtNewBalance);
		
		// Emit encrypted event
		ctUint256 memory ctFeeAmount = MpcCore.offBoardToUser(gtFeeAmount, LibAccount.getUserEncryptionAddress(quote.partyA));
		emit SharedEvents.BalanceChangePartyA(quote.partyA, ctFeeAmount, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);

		LibQuote.removeFromPendingQuotes(quote);
	}

}
