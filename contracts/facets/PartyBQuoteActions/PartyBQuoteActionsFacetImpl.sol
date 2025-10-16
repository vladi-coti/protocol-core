// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/muon/LibMuonPartyB.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibPartyBQuoteActions.sol";

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
		
		// Get encrypted available balance and decrypt
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableForQuote(upnlSig.upnl, msg.sender, quote.partyA);
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
		require(availableBalance >= 0, "PartyBFacet: Available balance is lower than zero");
		
		// Get encrypted totalForPartyB and decrypt
		GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
		gtUint256 gtTotalForPartyB = gtLockedValues.totalForPartyB();
		uint256 totalForPartyB = MpcCore.decrypt(gtTotalForPartyB);
		require(uint256(availableBalance) >= totalForPartyB, "PartyBFacet: insufficient available balance");
		
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
			accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote);
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
		accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
		accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote);

		// send trading Fee back to partyA
		gtUint256 gtFee = LibQuote.getTradingFee(quoteId);
		uint256 fee = MpcCore.decrypt(gtFee);
		
		// Update allocated balance with encrypted operations
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
		gtUint256 gtFeeAmount = MpcCore.setPublic256(fee);
		gtUint256 gtNewBalance = gtCurrentBalance.add(gtFeeAmount);
		accountLayout.allocatedBalances[quote.partyA] = MpcCore.offBoardCombined(gtNewBalance, quote.partyA);
		
		emit SharedEvents.BalanceChangePartyA(quote.partyA, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);

		LibQuote.removeFromPendingQuotes(quote);
	}
}
