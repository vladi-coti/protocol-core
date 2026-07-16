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
import "../../libraries/LibEncryption.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibOnChainUpnl.sol";
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
		LibEncryption.storePartyAPendingLockedBalance(accountLayout, quote.partyA, accountLayout.pendingLockedBalances[quote.partyA].subQuoteGarbled(quote));
		LibEncryption.storePartyBPendingLockedBalance(
			accountLayout,
			quote.partyB,
			quote.partyA,
			accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote)
		);

		// send trading Fee back to partyA
		gtUint256 gtFeeAmount = LibQuote.getTradingFee(quote.id);
		
		// Update allocated balance with encrypted operations
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
		gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtFeeAmount);
		LibEncryption.storePartyAAllocatedBalance(accountLayout, quote.partyA, gtNewBalance);
		
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
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		LibEncryption.storeQuoteRequestedClosePrice(quoteLayout, quote, gtZero);
		LibEncryption.storeQuoteQuantityToClose(quoteLayout, quote, gtZero);
	}

	function forceClosePosition(
		uint256 quoteId,
		HighLowPriceSig memory sig,
		SettlementSig memory settlementSig,
		uint256[] memory updatedPrices,
		QuotePriceSig memory partyAPriceSig,
		QuotePriceSig memory partyBPriceSig
	) public returns (gtUint256 gtClosePrice, bool isPartyBLiquidated, gtInt256 gtUpnlPartyB, gtUint256 gtPartyBAllocatedBalance) {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(quote.quoteStatus == QuoteStatus.CLOSE_PENDING, "PartyAFacet: Invalid state");
		require(block.timestamp <= quote.deadline, "PartyBFacet: Close request is expired");
		require(sig.endTime + maLayout.forceCloseSecondCooldown <= quote.deadline, "PartyBFacet: Close request is expired");
		require(quote.orderType == OrderType.LIMIT, "PartyBFacet: Quote's order type should be LIMIT");
		require(sig.startTime >= quote.statusModifyTimestamp + maLayout.forceCloseFirstCooldown, "PartyAFacet: Cooldown not reached");
		require(sig.endTime <= block.timestamp - maLayout.forceCloseSecondCooldown, "PartyAFacet: Cooldown not reached");
		require(sig.averagePrice <= sig.highest && sig.averagePrice >= sig.lowest, "PartyAFacet: Invalid average price");

		// H-04: authenticate Muon prices before any onboard/decrypt of private close predicates.
		LibMuonForceActions.verifyHighLowPrice(sig, quote.partyB, quote.partyA, quote.symbolId);
		if (updatedPrices.length > 0) {
			LibMuonSettlement.verifySettlement(settlementSig, quote.partyA);
		}

		gtClosePrice = _forceClosePrice(quote, sig, symbolLayout.forceCloseGapRatio[quote.symbolId], maLayout.forceClosePricePenalty);
		gtBool gtClosePriceEqAverage = gtClosePrice.eq(MpcCore.setPublic256(sig.averagePrice));
		if (MpcCore.decrypt(gtClosePriceEqAverage))
			require(sig.endTime - sig.startTime >= maLayout.forceCloseMinSigPeriod, "PartyAFacet: Invalid signature period");

		accountLayout.partyANonces[quote.partyA] += 1;
		accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;
		gtUint256 gtReserveAmount = LibAccount.initializeReserveVault(quote.partyB);
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);

		uint256[] memory quoteIds = new uint256[](1);
		gtUint256[] memory gtFilledAmounts = new gtUint256[](1);
		gtUint256[] memory gtClosedPrices = new gtUint256[](1);
		uint256[] memory marketPrices = new uint256[](1);
		quoteIds[0] = quoteId;
		gtFilledAmounts[0] = gtQuantityToClose;
		gtClosedPrices[0] = gtClosePrice;
		marketPrices[0] = sig.currentPrice;
		gtInt256 gtPartyBAvailableBalance;
		gtInt256 gtPartyAAvailableBalance;
		(gtPartyBAvailableBalance, gtPartyAAvailableBalance, gtUpnlPartyB) = LibSolvency.getAvailableBalanceAndPartyBUpnlAfterClosePosition(
			quoteIds,
			gtFilledAmounts,
			gtClosedPrices,
			marketPrices,
			LibOnChainUpnl.partyBUpnlFromQuotePrices(quote.partyB, quote.partyA, partyBPriceSig),
			LibOnChainUpnl.partyAUpnlFromQuotePrices(quote.partyA, partyAPriceSig),
			quote.partyB,
			quote.partyA
		);

		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtPartyAAvailableBalance.ge(gtZero)), "PartyAFacet: PartyA will be insolvent");

		if (MpcCore.decrypt(gtPartyBAvailableBalance.ge(gtZero))) {
			_settleAndClose(settlementSig, updatedPrices, quote, gtQuantityToClose, gtClosePrice);
		} else {
			gtInt256 gtWithReserve = gtPartyBAvailableBalance.checkedAdd(LibEncryption.toNonNegativeSigned(gtReserveAmount));
			if (MpcCore.decrypt(gtWithReserve.ge(gtZero))) {
				gtUint256 gtAvailableAmount = gtZero.checkedSub(gtPartyBAvailableBalance).fromSigned();
				LibEncryption.storeReserveVault(accountLayout, quote.partyB, gtReserveAmount.checkedSub(gtAvailableAmount));
				_creditPartyB(accountLayout, quote.partyB, quote.partyA, gtAvailableAmount);
				_settleAndClose(settlementSig, updatedPrices, quote, gtQuantityToClose, gtClosePrice);
			} else {
				LibEncryption.storeReserveVault(accountLayout, quote.partyB, MpcCore.setPublic256(uint256(0)));
				_creditPartyB(accountLayout, quote.partyB, quote.partyA, gtReserveAmount);
				isPartyBLiquidated = true;
				// H-26: unlock this quote's cva+lf on PartyB locks before liquidation reads LF.
				{
					GarbledLockedValues memory gtQuoteLocked = quote.lockedValues.onBoard();
					gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
					GarbledLockedValues memory gtPartyBLocked = accountLayout.partyBLockedBalances[quote.partyB][quote.partyA].onBoard();
					gtPartyBLocked.cva = gtPartyBLocked.cva.checkedSub(gtQuantityToClose.checkedMul(gtQuoteLocked.cva).div(gtOpenAmount));
					gtPartyBLocked.lf = gtPartyBLocked.lf.checkedSub(gtQuantityToClose.checkedMul(gtQuoteLocked.lf).div(gtOpenAmount));
					LibEncryption.storePartyBLockedBalance(accountLayout, quote.partyB, quote.partyA, gtPartyBLocked);
				}
				LibLiquidation.liquidatePartyBFromAvailable(quote.partyB, quote.partyA, gtWithReserve, block.timestamp, quote.partyA);
			}
		}
		gtPartyBAllocatedBalance = LockedValuesOps.safeOnboard(AccountStorage.layout().partyBAllocatedBalances[quote.partyB][quote.partyA].ciphertext);
	}

	function _forceClosePrice(
		Quote storage quote,
		HighLowPriceSig memory sig,
		uint256 gapRatio,
		uint256 penalty
	) private returns (gtUint256 gtClosePrice) {
		gtUint256 gtRequestedClosePrice = LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext);
		gtUint256 gtGapRatio = MpcCore.setPublic256(gapRatio);
		gtUint256 gtPenalty = MpcCore.setPublic256(penalty);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));
		gtUint256 gtAveragePrice = MpcCore.setPublic256(sig.averagePrice);
		gtUint256 gtGap = gtRequestedClosePrice.checkedMul(gtGapRatio).div(gtScaleFactor);
		gtUint256 gtPenaltyAmount = gtRequestedClosePrice.checkedMul(gtPenalty).div(gtScaleFactor);

		if (quote.positionType == PositionType.LONG) {
			require(MpcCore.decrypt(MpcCore.setPublic256(sig.highest).ge(gtRequestedClosePrice.checkedAdd(gtGap))), "PartyAFacet: Requested close price not reached");
			gtClosePrice = gtRequestedClosePrice.checkedAdd(gtPenaltyAmount);
			gtClosePrice = MpcCore.mux(gtClosePrice.gt(gtAveragePrice), gtAveragePrice, gtClosePrice);
		} else {
			require(MpcCore.decrypt(gtRequestedClosePrice.checkedSub(gtGap).ge(MpcCore.setPublic256(sig.lowest))), "PartyAFacet: Requested close price not reached");
			gtClosePrice = gtRequestedClosePrice.checkedSub(gtPenaltyAmount);
			gtClosePrice = MpcCore.mux(gtClosePrice.gt(gtAveragePrice), gtClosePrice, gtAveragePrice);
		}
	}

	function _settleAndClose(
		SettlementSig memory settlementSig,
		uint256[] memory updatedPrices,
		Quote storage quote,
		gtUint256 gtQuantityToClose,
		gtUint256 gtClosePrice
	) private {
		if (updatedPrices.length > 0) {
			LibSettlement.settleUpnl(settlementSig, updatedPrices, quote.partyA, true);
		}
		LibQuote.closeQuote(quote, gtQuantityToClose, gtClosePrice);
	}

	function _creditPartyB(AccountStorage.Layout storage accountLayout, address partyB, address partyA, gtUint256 gtAmount) private {
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
		LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtCurrentBalance.checkedAdd(gtAmount));
		ctUint256 memory ctAmount = MpcCore.offBoardToUser(gtAmount, LibAccount.getUserEncryptionAddress(partyB));
		emit SharedEvents.BalanceChangePartyB(partyB, partyA, ctAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
	}
}
