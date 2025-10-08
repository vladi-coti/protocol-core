// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./LibQuote.sol";

library LibPartyBPositionsActions {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	/**
	 * @notice Opens a position using private variables
	 * @param quoteId The ID of the quote
	 * @param filledAmount The amount to fill
	 * @param openedPrice The price at which to open
	 */
	function openPositionWithPrivacy(uint256 quoteId, uint256 filledAmount, uint256 openedPrice) internal returns (uint256 currentId) {
		return openPosition(quoteId, filledAmount, openedPrice);
	}

	function fillCloseRequest(uint256 quoteId, uint256 filledAmount, uint256 closedPrice) internal {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(
			quote.quoteStatus == QuoteStatus.CLOSE_PENDING || quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
			"PartyBFacet: Invalid state"
		);
		require(block.timestamp <= quote.deadline, "PartyBFacet: Quote is expired");
		
		// Decrypt requestedClosePrice for comparison
		gtUint256 gtRequestedClosePrice = LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext);
		uint256 requestedClosePrice = MpcCore.decrypt(gtRequestedClosePrice);
		
		if (quote.positionType == PositionType.LONG) {
			require(closedPrice >= requestedClosePrice, "PartyBFacet: Closed price isn't valid");
		} else {
			require(closedPrice <= requestedClosePrice, "PartyBFacet: Closed price isn't valid");
		}
		
		// Decrypt quantityToClose for validation
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);
		uint256 quantityToClose = MpcCore.decrypt(gtQuantityToClose);
		
		if (quote.orderType == OrderType.LIMIT) {
			require(quantityToClose >= filledAmount, "PartyBFacet: Invalid filledAmount");
		} else {
			require(quantityToClose == filledAmount, "PartyBFacet: Invalid filledAmount");
		}
		LibQuote.closeQuote(quote, filledAmount, closedPrice);
	}

	function openPosition(uint256 quoteId, uint256 filledAmount, uint256 openedPrice) internal returns (uint256 currentId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();

		Quote storage quote = quoteLayout.quotes[quoteId];
		require(SymbolStorage.layout().symbols[quote.symbolId].isValid, "PartyBFacet: Symbol is not valid");
		require(quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		require(block.timestamp <= quote.deadline, "PartyBFacet: Quote is expired");

		address feeCollector = appLayout.affiliateFeeCollector[quote.affiliate] == address(0)
			? appLayout.defaultFeeCollector
			: appLayout.affiliateFeeCollector[quote.affiliate];

		// Decrypt quantity for validation
		gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
		uint256 quoteQuantity = MpcCore.decrypt(gtQuantity);

		// Decrypt encrypted quote fields for fee calculation
		gtUint256 gtTradingFee = LockedValuesOps.safeOnboard(quote.tradingFee.ciphertext);
		gtUint256 gtFilledAmount = MpcCore.setPublic256(filledAmount);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e36));
		gtUint256 gtRequestedOpenPrice = LockedValuesOps.safeOnboard(quote.requestedOpenPrice.ciphertext);
		
		if (quote.orderType == OrderType.LIMIT) {
			require(quoteQuantity >= filledAmount && filledAmount > 0, "PartyBFacet: Invalid filledAmount");
			gtUint256 gtFee = gtFilledAmount.mul(gtRequestedOpenPrice).mul(gtTradingFee).div(gtScaleFactor);
			accountLayout.balances[feeCollector] += MpcCore.decrypt(gtFee);
		} else {
			require(quoteQuantity == filledAmount, "PartyBFacet: Invalid filledAmount");
			gtUint256 gtMarketPrice = LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext);
			gtUint256 gtFee = gtFilledAmount.mul(gtMarketPrice).mul(gtTradingFee).div(gtScaleFactor);
			accountLayout.balances[feeCollector] += MpcCore.decrypt(gtFee);
		}
		
		// Decrypt requestedOpenPrice for validation
		uint256 requestedOpenPrice = MpcCore.decrypt(gtRequestedOpenPrice);
		
		if (quote.positionType == PositionType.LONG) {
			require(openedPrice <= requestedOpenPrice, "PartyBFacet: Opened price isn't valid");
		} else {
			require(openedPrice >= requestedOpenPrice, "PartyBFacet: Opened price isn't valid");
		}

		// Store encrypted openedPrice
		gtUint256 gtOpenedPrice = MpcCore.setPublic256(openedPrice);
		quote.openedPrice = gtOpenedPrice.offBoardCombined(quote.partyA);
		quote.initialOpenedPrice = gtOpenedPrice.offBoardCombined(quote.partyA);
		quote.statusModifyTimestamp = block.timestamp;

		LibQuote.removeFromPendingQuotes(quote);

		if (quoteQuantity == filledAmount) {
			accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
			accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote);
			
			// Scale locked values by price ratio: lockedValues * openedPrice / requestedOpenPrice
			GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
			gtUint256 gtOpenedPriceValue = MpcCore.setPublic256(openedPrice);
			gtLockedValues = gtLockedValues.mul(gtOpenedPriceValue).div(gtRequestedOpenPrice);
			quote.lockedValues = gtLockedValues.offBoard(quote.partyA);

			// check locked values
			gtUint256 gtTotalForPartyA = gtLockedValues.totalForPartyA();
			gtUint256 gtMinValue = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue);
			require(MpcCore.decrypt(gtTotalForPartyA.ge(gtMinValue)), "PartyBFacet: Quote value is low");
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
			gtUint256 gtQuoteQuantity = MpcCore.setPublic256(quoteQuantity);
			GarbledLockedValues memory gtFilledLockedValues = gtQuoteLockedValues.mul(gtFilledAmount).div(gtQuoteQuantity);
			
			// Apply price scaling: filledLockedValues * openedPrice / requestedOpenPrice
			gtUint256 gtOpenedPriceValue = MpcCore.setPublic256(openedPrice);
			GarbledLockedValues memory gtAppliedFilledLockedValues = gtFilledLockedValues.mul(gtOpenedPriceValue).div(gtRequestedOpenPrice);
			
			// check that opened position is not minor position
			gtUint256 gtAppliedTotal = gtAppliedFilledLockedValues.totalForPartyA();
			gtUint256 gtMinValue = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue);
			require(MpcCore.decrypt(gtAppliedTotal.ge(gtMinValue)), "PartyBFacet: Quote value is low");
			
			// check that new pending position is not minor position
			if (newStatus != QuoteStatus.CANCELED) {
				gtUint256 gtRemainingTotal = gtQuoteLockedValues.totalForPartyA().sub(gtFilledLockedValues.totalForPartyA());
				require(MpcCore.decrypt(gtRemainingTotal.ge(gtMinValue)), "PartyBFacet: Quote value is low");
			}
			
			// Create encrypted zero values
			gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
			GarbledLockedValues memory gtZeroLocked = LockedValuesOps.makeZero();

			Quote memory q = Quote({
				id: currentId,
				partyBsWhiteList: quote.partyBsWhiteList,
				symbolId: quote.symbolId,
				positionType: quote.positionType,
				orderType: quote.orderType,
				openedPrice: gtZero.offBoardCombined(quote.partyA),
				initialOpenedPrice: gtZero.offBoardCombined(quote.partyA),
				requestedOpenPrice: quote.requestedOpenPrice,
				marketPrice: quote.marketPrice,
				quantity: MpcCore.setPublic256(quoteQuantity - filledAmount).offBoardCombined(quote.partyA),
				closedAmount: gtZero.offBoardCombined(quote.partyA),
				lockedValues: gtZeroLocked.offBoard(quote.partyA),
				initialLockedValues: gtZeroLocked.offBoard(quote.partyA),
				maxFundingRate: quote.maxFundingRate,
				partyA: quote.partyA,
				partyB: address(0),
				quoteStatus: newStatus,
				avgClosedPrice: gtZero.offBoardCombined(quote.partyA),
				requestedClosePrice: gtZero.offBoardCombined(quote.partyA),
				parentId: quote.id,
				createTimestamp: quote.createTimestamp,
				statusModifyTimestamp: block.timestamp,
				quantityToClose: gtZero.offBoardCombined(quote.partyA),
				lastFundingPaymentTimestamp: 0,
				deadline: quote.deadline,
				tradingFee: quote.tradingFee,
				affiliate: quote.affiliate
			});

			quoteLayout.quoteIdsOf[quote.partyA].push(currentId);
			quoteLayout.quotes[currentId] = q;
			Quote storage newQuote = quoteLayout.quotes[currentId];

			if (newStatus == QuoteStatus.CANCELED) {
				// send trading Fee back to partyA
				gtUint256 gtFee = LibQuote.getTradingFee(newQuote.id);
				uint256 fee = MpcCore.decrypt(gtFee);
				accountLayout.allocatedBalances[newQuote.partyA] += fee;
				emit SharedEvents.BalanceChangePartyA(newQuote.partyA, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);

				// part of quote has been filled and part of it has been canceled
				accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
				accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote);
			} else {
				// Subtract filled locked values from pending balances
				GarbledLockedValues memory gtPendingA = accountLayout.pendingLockedBalances[quote.partyA].onBoard();
				GarbledLockedValues memory gtResultA = gtPendingA.sub(gtFilledLockedValues);
				accountLayout.pendingLockedBalances[quote.partyA] = gtResultA.offBoard(quote.partyA);
				
				accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote);
			}
			
			// Calculate remaining locked values for the new quote
			GarbledLockedValues memory gtRemainingLocked = gtQuoteLockedValues.sub(gtFilledLockedValues);
			newQuote.lockedValues = gtRemainingLocked.offBoard(quote.partyA);
			newQuote.initialLockedValues = newQuote.lockedValues;

			// Update quote quantity with encrypted value
			quote.quantity = gtFilledAmount.offBoardCombined(quote.partyA);

			// Update quote locked values with applied (price-adjusted) values
			quote.lockedValues = gtAppliedFilledLockedValues.offBoard(quote.partyA);
		}
		// lock with amount of filledAmount
		accountLayout.lockedBalances[quote.partyA].addQuote(quote);
		accountLayout.partyBLockedBalances[quote.partyB][quote.partyA].addQuote(quote);

		// check leverage (is in 18 decimals): (quantity * openedPrice) / totalForPartyA <= maxLeverage
		gtUint256 gtFinalQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
		gtUint256 gtFinalOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
		GarbledLockedValues memory gtFinalLockedValues = quote.lockedValues.onBoard();
		gtUint256 gtFinalTotal = gtFinalLockedValues.totalForPartyA();
		gtUint256 gtLeverage = gtFinalQuantity.mul(gtFinalOpenedPrice).div(gtFinalTotal);
		gtUint256 gtMaxLeverage = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].maxLeverage);
		require(MpcCore.decrypt(gtLeverage.le(gtMaxLeverage)), "PartyBFacet: Leverage is high");

		quote.quoteStatus = QuoteStatus.OPENED;
		LibQuote.addToOpenPositions(quoteId);
	}
}
