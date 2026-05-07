// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./LibQuote.sol";
import "./LibEncryption.sol";

library LibPartyBPositionsActions {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function fillCloseRequest(uint256 quoteId, gtUint256 gtFilledAmount, gtUint256 gtClosedPrice) internal {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(
			quote.quoteStatus == QuoteStatus.CLOSE_PENDING || quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
			"PBF:state"
		);
		require(block.timestamp <= quote.deadline, "PBF:exp");
		
		gtUint256 gtRequestedClosePrice = LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext);
		gtBool gtPriceValid = quote.positionType == PositionType.LONG 
			? gtClosedPrice.ge(gtRequestedClosePrice)
			: gtClosedPrice.le(gtRequestedClosePrice);
		require(MpcCore.decrypt(gtPriceValid), "PBF:price");
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);
		gtBool gtFilledAmountValid = quote.orderType == OrderType.LIMIT
			? gtQuantityToClose.ge(gtFilledAmount)
			: gtQuantityToClose.eq(gtFilledAmount);
		require(MpcCore.decrypt(gtFilledAmountValid), "PBF:fill");
		
		// Call closeQuote with encrypted values
		LibQuote.closeQuote(quote, gtFilledAmount, gtClosedPrice);
	}

	function openPosition(uint256 quoteId, gtUint256 gtFilledAmount, gtUint256 gtOpenedPrice) internal returns (uint256 currentId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();

		Quote storage quote = quoteLayout.quotes[quoteId];
		require(SymbolStorage.layout().symbols[quote.symbolId].isValid, "PBF:symbol");
		require(quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING, "PBF:state");
		require(block.timestamp <= quote.deadline, "PBF:exp");

		address feeCollector = appLayout.affiliateFeeCollector[quote.affiliate] != address(0)
			? appLayout.affiliateFeeCollector[quote.affiliate]
			: appLayout.defaultFeeCollector;

		// Decrypt quantity for validation
		gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);

		// Decrypt trading fee RATE stored on quote and scale factor
		gtUint256 gtTradingFeeRate = LockedValuesOps.safeOnboard(quote.tradingFee.ciphertext);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e36));
		gtUint256 gtRequestedOpenPrice = LockedValuesOps.safeOnboard(quote.requestedOpenPrice.ciphertext);
		
		gtUint256 gtFee;
		if (quote.orderType == OrderType.LIMIT) {
			require(MpcCore.decrypt(gtQuantity.ge(gtFilledAmount).and(gtFilledAmount.gt(MpcCore.setPublic256(uint256(0))))), "PBF:fill");
			gtFee = gtFilledAmount.checkedMul(gtRequestedOpenPrice).checkedMul(gtTradingFeeRate).div(gtScaleFactor);
		} else {
			require(MpcCore.decrypt(gtQuantity.eq(gtFilledAmount)), "PBF:fill");
			gtFee = gtFilledAmount.checkedMul(LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext)).checkedMul(gtTradingFeeRate).div(gtScaleFactor);
		}
		gtUint256 gtFeeCollectorBalance = LibAccount.initializeFeeCollectorBalance(feeCollector);
		LibEncryption.storeFeeCollectorBalance(accountLayout, feeCollector, gtFeeCollectorBalance.checkedAdd(gtFee));
		
		gtBool gtOpenedPriceValid = quote.positionType == PositionType.LONG
			? gtOpenedPrice.le(gtRequestedOpenPrice)
			: gtOpenedPrice.ge(gtRequestedOpenPrice);
		require(MpcCore.decrypt(gtOpenedPriceValid), "PBF:open px");

		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		LibEncryption.storeQuoteOpenedPrice(quoteLayout, quote, gtOpenedPrice);
		LibEncryption.storeQuoteInitialOpenedPrice(quoteLayout, quote, gtOpenedPrice);
		quote.statusModifyTimestamp = block.timestamp;
		LibQuote.removeFromPendingQuotes(quote);
		if (MpcCore.decrypt(gtQuantity.eq(gtFilledAmount))) {
			GarbledLockedValues memory gtPartyAPending = accountLayout.pendingLockedBalances[quote.partyA].subQuoteGarbled(quote);
			LibEncryption.storePartyAPendingLockedBalance(accountLayout, quote.partyA, gtPartyAPending);
			GarbledLockedValues memory gtPartyBPending = accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote);
			LibEncryption.storePartyBPendingLockedBalance(accountLayout, quote.partyB, quote.partyA, gtPartyBPending);
			GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
			gtLockedValues = gtLockedValues.mul(gtOpenedPrice).div(gtRequestedOpenPrice);
			gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
			LibEncryption.storeQuoteRequestedOpenPrice(quoteLayout, quote, gtRequestedOpenPrice);
			LibEncryption.storeQuoteMarketPrice(quoteLayout, quote, LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext));
			LibEncryption.storeQuoteQuantity(quoteLayout, quote, gtQuantity);
			LibEncryption.storeQuoteClosedAmount(quoteLayout, quote, gtZero);
			LibEncryption.storeQuoteAvgClosedPrice(quoteLayout, quote, gtZero);
			LibEncryption.storeQuoteRequestedClosePrice(quoteLayout, quote, gtZero);
			LibEncryption.storeQuoteQuantityToClose(quoteLayout, quote, gtZero);
			LibEncryption.storeQuoteTradingFee(quoteLayout, quote, gtTradingFeeRate);
			LibEncryption.storeQuoteLockedValues(quoteLayout, quote, gtLockedValues);

			// check locked values
			gtUint256 gtTotalForPartyA = gtLockedValues.totalForPartyA();
			gtUint256 gtMinValue = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue);
			require(MpcCore.decrypt(gtTotalForPartyA.ge(gtMinValue)), "PBF:value");
		}
		// partially fill
		else {
			currentId = ++quoteLayout.lastId;
			QuoteStatus newStatus;
			if (quote.quoteStatus == QuoteStatus.CANCEL_PENDING) {
				newStatus = QuoteStatus.CANCELED;
			} else {
				newStatus = QuoteStatus.PENDING;
				quoteLayout.partyAPendingQuotes[quote.partyA].push(currentId);
			}
			
			// Calculate filled locked values with encryption
			GarbledLockedValues memory gtQuoteLockedValues = quote.lockedValues.onBoard();
			GarbledLockedValues memory gtFilledLockedValues = gtQuoteLockedValues.mul(gtFilledAmount).div(gtQuantity);
			
			// Apply price scaling: filledLockedValues * openedPrice / requestedOpenPrice
			GarbledLockedValues memory gtAppliedFilledLockedValues = gtFilledLockedValues.mul(gtOpenedPrice).div(gtRequestedOpenPrice);
			
			// check that opened position is not minor position
			gtUint256 gtAppliedTotal = gtAppliedFilledLockedValues.totalForPartyA();
			gtUint256 gtMinValue = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue);
			require(MpcCore.decrypt(gtAppliedTotal.ge(gtMinValue)), "PBF:value");
			
			// check that new pending position is not minor position
			if (newStatus != QuoteStatus.CANCELED) {
				gtUint256 gtRemainingTotal = gtQuoteLockedValues.totalForPartyA().checkedSub(gtFilledLockedValues.totalForPartyA());
				require(MpcCore.decrypt(gtRemainingTotal.ge(gtMinValue)), "PBF:value");
			}
			
			gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
			GarbledLockedValues memory gtZeroLocked = LockedValuesOps.makeZero();
			Quote memory q = Quote({
				id: currentId,
				partyBsWhiteList: quote.partyBsWhiteList,
				symbolId: quote.symbolId,
				positionType: quote.positionType,
				orderType: quote.orderType,
				openedPrice: gtZero.offBoardCombined(partyAAddr),
				initialOpenedPrice: gtZero.offBoardCombined(partyAAddr),
				requestedOpenPrice: quote.requestedOpenPrice,
				marketPrice: quote.marketPrice,
				quantity: gtQuantity.checkedSub(gtFilledAmount).offBoardCombined(partyAAddr),
				closedAmount: gtZero.offBoardCombined(partyAAddr),
				lockedValues: gtZeroLocked.offBoard(partyAAddr),
				initialLockedValues: gtZeroLocked.offBoard(partyAAddr),
				maxFundingRate: quote.maxFundingRate,
				partyA: quote.partyA,
				partyB: address(0),
				quoteStatus: newStatus,
				avgClosedPrice: gtZero.offBoardCombined(partyAAddr),
				requestedClosePrice: gtZero.offBoardCombined(partyAAddr),
				parentId: quote.id,
				createTimestamp: quote.createTimestamp,
				statusModifyTimestamp: block.timestamp,
				quantityToClose: gtZero.offBoardCombined(partyAAddr),
				lastFundingPaymentTimestamp: 0,
				deadline: quote.deadline,
				tradingFee: quote.tradingFee,
				affiliate: quote.affiliate
			});

			quoteLayout.quoteIdsOf[quote.partyA].push(currentId);
			quoteLayout.quotes[currentId] = q;
			Quote storage newQuote = quoteLayout.quotes[currentId];
			LibEncryption.storeQuoteOpenedPrice(quoteLayout, newQuote, gtZero);
			LibEncryption.storeQuoteInitialOpenedPrice(quoteLayout, newQuote, gtZero);
			LibEncryption.storeQuoteRequestedOpenPrice(quoteLayout, newQuote, gtRequestedOpenPrice);
			LibEncryption.storeQuoteMarketPrice(quoteLayout, newQuote, LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext));
			LibEncryption.storeQuoteQuantity(quoteLayout, newQuote, gtQuantity.checkedSub(gtFilledAmount));
			LibEncryption.storeQuoteClosedAmount(quoteLayout, newQuote, gtZero);
			LibEncryption.storeQuoteAvgClosedPrice(quoteLayout, newQuote, gtZero);
			LibEncryption.storeQuoteRequestedClosePrice(quoteLayout, newQuote, gtZero);
			LibEncryption.storeQuoteQuantityToClose(quoteLayout, newQuote, gtZero);
			LibEncryption.storeQuoteTradingFee(quoteLayout, newQuote, gtTradingFeeRate);

			if (newStatus == QuoteStatus.CANCELED) {
				// send trading Fee back to partyA
				gtUint256 gtFeeAmount = LibQuote.getTradingFee(newQuote.id);
				
				address newQuotePartyAAddr = LibAccount.getUserEncryptionAddress(newQuote.partyA);
				gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[newQuote.partyA].ciphertext);
				LibEncryption.storePartyAAllocatedBalance(accountLayout, newQuote.partyA, gtCurrentBalance.checkedAdd(gtFeeAmount));
				emit SharedEvents.BalanceChangePartyA(newQuote.partyA, MpcCore.offBoardToUser(gtFeeAmount, newQuotePartyAAddr), SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
				GarbledLockedValues memory gtPartyAPending = accountLayout.pendingLockedBalances[quote.partyA].subQuoteGarbled(quote);
				LibEncryption.storePartyAPendingLockedBalance(accountLayout, quote.partyA, gtPartyAPending);
				GarbledLockedValues memory gtPartyBPending = accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote);
				LibEncryption.storePartyBPendingLockedBalance(accountLayout, quote.partyB, quote.partyA, gtPartyBPending);
			} else {
				LibEncryption.storePartyAPendingLockedBalance(
					accountLayout,
					quote.partyA,
					accountLayout.pendingLockedBalances[quote.partyA].onBoard().sub(gtFilledLockedValues)
				);
				GarbledLockedValues memory gtPartyBPending = accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote);
				LibEncryption.storePartyBPendingLockedBalance(accountLayout, quote.partyB, quote.partyA, gtPartyBPending);
			}
			GarbledLockedValues memory gtRemainingLocked = gtQuoteLockedValues.sub(gtFilledLockedValues);
			LibEncryption.storeQuoteLockedValues(quoteLayout, newQuote, gtRemainingLocked);
			LibEncryption.storeQuoteInitialLockedValues(quoteLayout, newQuote, gtRemainingLocked);
			LibEncryption.storeQuoteQuantity(quoteLayout, quote, gtFilledAmount);
			LibEncryption.storeQuoteLockedValues(quoteLayout, quote, gtAppliedFilledLockedValues);
		}
		GarbledLockedValues memory gtPartyALocked = accountLayout.lockedBalances[quote.partyA].addQuoteGarbled(quote);
		LibEncryption.storePartyALockedBalance(accountLayout, quote.partyA, gtPartyALocked);
		GarbledLockedValues memory gtPartyBLocked = accountLayout.partyBLockedBalances[quote.partyB][quote.partyA].addQuoteGarbled(quote);
		LibEncryption.storePartyBLockedBalance(accountLayout, quote.partyB, quote.partyA, gtPartyBLocked);

		// check leverage (is in 18 decimals): (quantity * openedPrice) / totalForPartyA <= maxLeverage
		gtUint256 gtFinalQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
		gtUint256 gtFinalOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
		GarbledLockedValues memory gtFinalLockedValues = quote.lockedValues.onBoard();
		gtUint256 gtFinalTotal = gtFinalLockedValues.totalForPartyA();
		gtUint256 gtLeverage = gtFinalQuantity.checkedMul(gtFinalOpenedPrice).div(gtFinalTotal);
		gtUint256 gtMaxLeverage = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].maxLeverage);
		require(MpcCore.decrypt(gtLeverage.le(gtMaxLeverage)), "PBF:lev");

		quote.quoteStatus = QuoteStatus.OPENED;
		LibQuote.addToOpenPositions(quoteId);
	}
}
