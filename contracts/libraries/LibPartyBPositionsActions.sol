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

	function fillCloseRequest(uint256 quoteId, gtUint256 gtFilledAmount, gtUint256 gtClosedPrice) internal {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(
			quote.quoteStatus == QuoteStatus.CLOSE_PENDING || quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
			"PartyBFacet: Invalid state"
		);
		require(block.timestamp <= quote.deadline, "PartyBFacet: Quote is expired");
		
		gtUint256 gtRequestedClosePrice = LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext);
		gtBool gtPriceValid = quote.positionType == PositionType.LONG 
			? gtClosedPrice.ge(gtRequestedClosePrice)
			: gtClosedPrice.le(gtRequestedClosePrice);
		require(MpcCore.decrypt(gtPriceValid), "PartyBFacet: Closed price isn't valid");
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);
		gtBool gtFilledAmountValid = quote.orderType == OrderType.LIMIT
			? gtQuantityToClose.ge(gtFilledAmount)
			: gtQuantityToClose.eq(gtFilledAmount);
		require(MpcCore.decrypt(gtFilledAmountValid), "PartyBFacet: Invalid filledAmount");
		
		// Call closeQuote with encrypted values
		LibQuote.closeQuote(quote, gtFilledAmount, gtClosedPrice);
	}

	function openPosition(uint256 quoteId, gtUint256 gtFilledAmount, gtUint256 gtOpenedPrice) internal returns (uint256 currentId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();

		Quote storage quote = quoteLayout.quotes[quoteId];
		require(SymbolStorage.layout().symbols[quote.symbolId].isValid, "PartyBFacet: Symbol is not valid");
		require(quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		require(block.timestamp <= quote.deadline, "PartyBFacet: Quote is expired");

		address feeCollector = appLayout.affiliateFeeCollector[quote.affiliate] != address(0)
			? appLayout.affiliateFeeCollector[quote.affiliate]
			: appLayout.defaultFeeCollector;

		// Decrypt quantity for validation
		gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
		uint256 quoteQuantity = MpcCore.decrypt(gtQuantity);

		// Decrypt trading fee RATE stored on quote and scale factor
		gtUint256 gtTradingFeeRate = LockedValuesOps.safeOnboard(quote.tradingFee.ciphertext);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e36));
		gtUint256 gtRequestedOpenPrice = LockedValuesOps.safeOnboard(quote.requestedOpenPrice.ciphertext);
		
		gtUint256 gtFee;
		if (quote.orderType == OrderType.LIMIT) {
			require(MpcCore.decrypt(gtQuantity.ge(gtFilledAmount).and(gtFilledAmount.gt(MpcCore.setPublic256(uint256(0))))), "PartyBFacet: Invalid filledAmount");
			gtFee = gtFilledAmount.mul(gtRequestedOpenPrice).mul(gtTradingFeeRate).div(gtScaleFactor);
		} else {
			require(MpcCore.decrypt(gtQuantity.eq(gtFilledAmount)), "PartyBFacet: Invalid filledAmount");
			gtFee = gtFilledAmount.mul(LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext)).mul(gtTradingFeeRate).div(gtScaleFactor);
		}
		accountLayout.balances[feeCollector] += MpcCore.decrypt(gtFee);
		
		gtBool gtOpenedPriceValid = quote.positionType == PositionType.LONG
			? gtOpenedPrice.le(gtRequestedOpenPrice)
			: gtOpenedPrice.ge(gtRequestedOpenPrice);
		require(MpcCore.decrypt(gtOpenedPriceValid), "PartyBFacet: Opened price isn't valid");

		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		address partyBAddr = LibAccount.getUserEncryptionAddress(quote.partyB);
		quote.openedPrice = gtOpenedPrice.offBoardCombined(partyAAddr);
		quote.initialOpenedPrice = gtOpenedPrice.offBoardCombined(partyAAddr);
		quote.statusModifyTimestamp = block.timestamp;
		LibQuote.removeFromPendingQuotes(quote);
		if (quoteQuantity == MpcCore.decrypt(gtFilledAmount)) {
			accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote, partyAAddr);
			accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote, partyBAddr);
			GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
			gtLockedValues = gtLockedValues.mul(gtOpenedPrice).div(gtRequestedOpenPrice);
			quote.lockedValues = gtLockedValues.offBoard(partyAAddr);

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
			GarbledLockedValues memory gtFilledLockedValues = gtQuoteLockedValues.mul(gtFilledAmount).div(gtQuantity);
			
			// Apply price scaling: filledLockedValues * openedPrice / requestedOpenPrice
			GarbledLockedValues memory gtAppliedFilledLockedValues = gtFilledLockedValues.mul(gtOpenedPrice).div(gtRequestedOpenPrice);
			
			// check that opened position is not minor position
			gtUint256 gtAppliedTotal = gtAppliedFilledLockedValues.totalForPartyA();
			gtUint256 gtMinValue = MpcCore.setPublic256(SymbolStorage.layout().symbols[quote.symbolId].minAcceptableQuoteValue);
			require(MpcCore.decrypt(gtAppliedTotal.ge(gtMinValue)), "PartyBFacet: Quote value is low");
			
			// check that new pending position is not minor position
			if (newStatus != QuoteStatus.CANCELED) {
				gtUint256 gtRemainingTotal = gtQuoteLockedValues.totalForPartyA().sub(gtFilledLockedValues.totalForPartyA());
				require(MpcCore.decrypt(gtRemainingTotal.ge(gtMinValue)), "PartyBFacet: Quote value is low");
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
				quantity: gtQuantity.sub(gtFilledAmount).offBoardCombined(partyAAddr),
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

			if (newStatus == QuoteStatus.CANCELED) {
				// send trading Fee back to partyA
				gtUint256 gtFee = LibQuote.getTradingFee(newQuote.id);
				uint256 fee = MpcCore.decrypt(gtFee);
				
				address newQuotePartyAAddr = LibAccount.getUserEncryptionAddress(newQuote.partyA);
				gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[newQuote.partyA].ciphertext);
				gtUint256 gtFeeAmount = MpcCore.setPublic256(fee);
				accountLayout.allocatedBalances[newQuote.partyA] = MpcCore.offBoardCombined(gtCurrentBalance.add(gtFeeAmount), newQuotePartyAAddr);
				emit SharedEvents.BalanceChangePartyA(newQuote.partyA, MpcCore.offBoardToUser(gtFeeAmount, newQuotePartyAAddr), SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
				accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote, partyAAddr);
				accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote, partyBAddr);
			} else {
				accountLayout.pendingLockedBalances[quote.partyA] = accountLayout.pendingLockedBalances[quote.partyA].onBoard().sub(gtFilledLockedValues).offBoard(partyAAddr);
				accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote, partyBAddr);
			}
			GarbledLockedValues memory gtRemainingLocked = gtQuoteLockedValues.sub(gtFilledLockedValues);
			newQuote.lockedValues = gtRemainingLocked.offBoard(partyAAddr);
			newQuote.initialLockedValues = newQuote.lockedValues;
			quote.quantity = gtFilledAmount.offBoardCombined(partyAAddr);
			quote.lockedValues = gtAppliedFilledLockedValues.offBoard(partyAAddr);
		}
		accountLayout.lockedBalances[quote.partyA].addQuote(quote, partyAAddr);
		accountLayout.partyBLockedBalances[quote.partyB][quote.partyA].addQuote(quote, partyBAddr);

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
