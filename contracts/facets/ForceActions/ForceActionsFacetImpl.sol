// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/muon/LibMuonForceActions.sol";
import "../../libraries/muon/LibMuonSettlement.sol";
import "../../libraries/LibSettlement.sol";
import "../../libraries/LibLiquidation.sol";
import "../../libraries/LibSolvency.sol";
import "../../storages/QuoteStorage.sol";

library ForceActionsFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function forceCancelQuote(uint256 quoteId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.CANCEL_PENDING, "PartyAFacet: Invalid state");
		require(block.timestamp > quote.statusModifyTimestamp + maLayout.forceCancelCooldown, "PartyAFacet: Cooldown not reached");
		quote.statusModifyTimestamp = block.timestamp;
		quote.quoteStatus = QuoteStatus.CANCELED;
		accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote, LibAccount.getUserEncryptionAddress(quote.partyA));
		accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote, LibAccount.getUserEncryptionAddress(quote.partyB));

		// send trading Fee back to partyA
		gtUint256 gtFeeAmount = LibQuote.getTradingFee(quote.id);
		
		// Update allocated balance with encrypted operations
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
		gtUint256 gtNewBalance = gtCurrentBalance.add(gtFeeAmount);
		accountLayout.allocatedBalances[quote.partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(quote.partyA));
		
		// Emit encrypted event
		ctUint256 memory ctFeeAmount = MpcCore.offBoardToUser(gtFeeAmount, LibAccount.getUserEncryptionAddress(quote.partyA));
		emit SharedEvents.BalanceChangePartyA(quote.partyA, ctFeeAmount, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);

		LibQuote.removeFromPendingQuotes(quote);
	}

	function forceCancelCloseRequest(uint256 quoteId) internal {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING, "PartyAFacet: Invalid state");
		require(block.timestamp > quote.statusModifyTimestamp + maLayout.forceCancelCloseCooldown, "PartyAFacet: Cooldown not reached");

		quote.statusModifyTimestamp = block.timestamp;
		quote.quoteStatus = QuoteStatus.OPENED;
		
		// Set encrypted fields to zero
		gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
		quote.requestedClosePrice = gtZero.offBoardCombined(partyAEncryptionAddress);
		quote.quantityToClose = gtZero.offBoardCombined(partyAEncryptionAddress);
	}

	function forceClosePosition(
		uint256 quoteId,
		HighLowPriceSig memory sig,
		SettlementSig memory settlementSig,
		uint256[] memory updatedPrices
	) internal returns (gtUint256 gtClosePrice, bool isPartyBLiquidated, gtInt256 gtUpnlPartyB, gtUint256 gtPartyBAllocatedBalance) {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(quote.quoteStatus == QuoteStatus.CLOSE_PENDING, "PartyAFacet: Invalid state");
		require(sig.endTime + maLayout.forceCloseSecondCooldown <= quote.deadline, "PartyBFacet: Close request is expired");
		require(quote.orderType == OrderType.LIMIT, "PartyBFacet: Quote's order type should be LIMIT");
		require(sig.startTime >= quote.statusModifyTimestamp + maLayout.forceCloseFirstCooldown, "PartyAFacet: Cooldown not reached");
		require(sig.endTime <= block.timestamp - maLayout.forceCloseSecondCooldown, "PartyAFacet: Cooldown not reached");
		require(sig.averagePrice <= sig.highest && sig.averagePrice >= sig.lowest, "PartyAFacet: Invalid average price");
		
		// Get encrypted requestedClosePrice
		gtUint256 gtRequestedClosePrice = LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext);
		
		// Calculate closePrice using encrypted operations
		gtUint256 gtGapRatio = MpcCore.setPublic256(symbolLayout.forceCloseGapRatio[quote.symbolId]);
		gtUint256 gtPenalty = MpcCore.setPublic256(maLayout.forceClosePricePenalty);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));
		
		if (quote.positionType == PositionType.LONG) {
			// Calculate encrypted minimum: gtRequestedClosePrice + (gtRequestedClosePrice * gtGapRatio) / 1e18
			gtUint256 gtGap = gtRequestedClosePrice.mul(gtGapRatio).div(gtScaleFactor);
			gtUint256 gtMinimum = gtRequestedClosePrice.add(gtGap);
			
			// Check require using encrypted comparison
			gtUint256 gtHighest = MpcCore.setPublic256(sig.highest);
			gtBool gtValid = gtHighest.ge(gtMinimum);
			require(MpcCore.decrypt(gtValid), "PartyAFacet: Requested close price not reached");
			
			// Calculate closePrice: gtRequestedClosePrice + (gtRequestedClosePrice * gtPenalty) / 1e18
			gtUint256 gtPenaltyAmount = gtRequestedClosePrice.mul(gtPenalty).div(gtScaleFactor);
			gtClosePrice = gtRequestedClosePrice.add(gtPenaltyAmount);
			
			// Max with average: if gtClosePrice > sig.averagePrice then gtClosePrice else sig.averagePrice
			gtUint256 gtAveragePrice = MpcCore.setPublic256(sig.averagePrice);
			gtBool gtClosePriceGtAverage = gtClosePrice.gt(gtAveragePrice);
			gtClosePrice = MpcCore.mux(gtClosePriceGtAverage, gtClosePrice, gtAveragePrice);
		} else {
			// Calculate encrypted maximum: gtRequestedClosePrice - (gtRequestedClosePrice * gtGapRatio) / 1e18
			gtUint256 gtGap = gtRequestedClosePrice.mul(gtGapRatio).div(gtScaleFactor);
			gtUint256 gtMaximum = gtRequestedClosePrice.sub(gtGap);
			
			// Check require using encrypted comparison
			gtUint256 gtLowest = MpcCore.setPublic256(sig.lowest);
			gtBool gtValid = gtMaximum.ge(gtLowest);
			require(MpcCore.decrypt(gtValid), "PartyAFacet: Requested close price not reached");
			
			// Calculate closePrice: gtRequestedClosePrice - (gtRequestedClosePrice * gtPenalty) / 1e18
			gtUint256 gtPenaltyAmount = gtRequestedClosePrice.mul(gtPenalty).div(gtScaleFactor);
			gtClosePrice = gtRequestedClosePrice.sub(gtPenaltyAmount);
			
			// Min with average: if gtClosePrice < sig.averagePrice then gtClosePrice else sig.averagePrice
			gtUint256 gtAveragePrice = MpcCore.setPublic256(sig.averagePrice);
			gtBool gtAveragePriceGtClose = gtAveragePrice.gt(gtClosePrice);
			gtClosePrice = MpcCore.mux(gtAveragePriceGtClose, gtClosePrice, gtAveragePrice);
		}

		// Check if closePrice equals averagePrice (decrypt for comparison)
		gtUint256 gtAveragePrice = MpcCore.setPublic256(sig.averagePrice);
		gtBool gtClosePriceEqAverage = gtClosePrice.eq(gtAveragePrice);
		if (MpcCore.decrypt(gtClosePriceEqAverage))
			require(sig.endTime - sig.startTime >= maLayout.forceCloseMinSigPeriod, "PartyAFacet: Invalid signature period");

		LibMuonForceActions.verifyHighLowPrice(sig, quote.partyB, quote.partyA, quote.symbolId);
		if (updatedPrices.length > 0) {
			LibMuonSettlement.verifySettlement(settlementSig, quote.partyA);
		}
		accountLayout.partyANonces[quote.partyA] += 1;
		accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;
		uint256 reserveAmount = accountLayout.reserveVault[quote.partyB];

		// Get encrypted quantityToClose
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);

		uint256[] memory quoteIds = new uint256[](1);
		gtUint256[] memory gtFilledAmounts = new gtUint256[](1);
		gtUint256[] memory gtClosedPrices = new gtUint256[](1);
		uint256[] memory marketPrices = new uint256[](1);
		quoteIds[0] = quoteId;
		gtFilledAmounts[0] = gtQuantityToClose;
		gtClosedPrices[0] = gtClosePrice;
		gtUpnlPartyB = MpcCore.setPublic256(uint256(0)).toSigned(); // Initialize to zero
		marketPrices[0] = sig.currentPrice;
		(gtInt256 gtPartyBAvailableBalance, gtInt256 gtPartyAAvailableBalance) = LibSolvency.getAvailableBalanceAfterClosePosition(
			quoteIds,
			gtFilledAmounts,
			gtClosedPrices,
			marketPrices,
			sig.upnlPartyB,
			sig.upnlPartyA,
			quote.partyB,
			quote.partyA
		);
		
		// Check PartyA is solvent using encrypted comparison
		gtInt256 gtZero = MpcCore.setPublic256(uint256(0)).toSigned();
		gtBool gtPartyASolvent = gtPartyAAvailableBalance.ge(gtZero);
		require(MpcCore.decrypt(gtPartyASolvent), "PartyAFacet: PartyA will be insolvent");
		
		// Check PartyB balance using encrypted comparisons
		gtBool gtPartyBSolvent = gtPartyBAvailableBalance.ge(gtZero);
		if (MpcCore.decrypt(gtPartyBSolvent)) {
			if (updatedPrices.length > 0) {
				LibSettlement.settleUpnl(settlementSig, updatedPrices, msg.sender, true);
			}
			LibQuote.closeQuote(quote, gtQuantityToClose, gtClosePrice);
		} else {
			// Check if PartyB has enough reserve using encrypted comparison
			gtUint256 gtReserveAmount = MpcCore.setPublic256(reserveAmount);
			gtInt256 gtWithReserve = gtPartyBAvailableBalance.add(gtReserveAmount.toSigned());
			gtBool gtCanUseReserve = gtWithReserve.ge(gtZero);
			if (MpcCore.decrypt(gtCanUseReserve)) {
				// Calculate available amount using encrypted operations
				// available = -partyBAvailableBalance (negate to get the deficit amount)
				gtInt256 gtNegBalance = gtZero.sub(gtPartyBAvailableBalance);
				
				// Decrypt only for reserve vault update (public storage)
				int256 negBalance = MpcCore.decrypt(gtNegBalance);
				uint256 available = uint256(negBalance);
				accountLayout.reserveVault[quote.partyB] -= available;
				
				// Update PartyB allocated balance with encrypted operations
				gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA].ciphertext);
				gtUint256 gtAvailableAmount = MpcCore.setPublic256(available);
				gtUint256 gtNewBalance = gtCurrentBalance.add(gtAvailableAmount);
				accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(quote.partyB));
				
				// Emit encrypted event
				ctUint256 memory ctAvailableAmount = MpcCore.offBoardToUser(gtAvailableAmount, LibAccount.getUserEncryptionAddress(quote.partyB));
				emit SharedEvents.BalanceChangePartyB(quote.partyB, quote.partyA, ctAvailableAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
				if (updatedPrices.length > 0) {
					LibSettlement.settleUpnl(settlementSig, updatedPrices, msg.sender, true);
				}
				LibQuote.closeQuote(quote, gtQuantityToClose, gtClosePrice);
			} else {
				accountLayout.reserveVault[quote.partyB] = 0;
				
				// Update PartyB allocated balance with encrypted operations
				gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA].ciphertext);
				gtUint256 gtReserveAmount = MpcCore.setPublic256(reserveAmount);
				gtUint256 gtNewBalance = gtCurrentBalance.add(gtReserveAmount);
				accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(quote.partyB));
				
				// Emit encrypted event
				ctUint256 memory ctReserveAmount = MpcCore.offBoardToUser(gtReserveAmount, LibAccount.getUserEncryptionAddress(quote.partyB));
				emit SharedEvents.BalanceChangePartyB(quote.partyB, quote.partyA, ctReserveAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
				// Decrypt for diff calculation (needed for liquidation)
				uint256 quantityToClose = MpcCore.decrypt(gtQuantityToClose);
				uint256 closePrice = MpcCore.decrypt(gtClosePrice);
				int256 diff = (int256(quantityToClose) * (int256(closePrice) - int256(sig.currentPrice))) / 1e18;
				if (quote.positionType == PositionType.LONG) {
					diff = diff * -1;
				}
				isPartyBLiquidated = true;
				int256 upnlPartyBPlain = sig.upnlPartyB + diff;
				LibLiquidation.liquidatePartyB(quote.partyB, quote.partyA, upnlPartyBPlain, block.timestamp);
				gtUpnlPartyB = MpcCore.setPublic256(uint256(upnlPartyBPlain)).toSigned();
			}
		}
		// Get encrypted PartyB allocated balance for return (get fresh value)
		gtPartyBAllocatedBalance = LockedValuesOps.safeOnboard(AccountStorage.layout().partyBAllocatedBalances[quote.partyB][quote.partyA].ciphertext);
	}
}
