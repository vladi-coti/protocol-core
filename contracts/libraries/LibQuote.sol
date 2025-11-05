// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./LibLockedValues.sol";
import "./LibAccount.sol";
import "../libraries/SharedEvents.sol";
import "../storages/QuoteStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/GlobalAppStorage.sol";
import "../storages/SymbolStorage.sol";
import "../storages/MAStorage.sol";

library LibQuote {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	/**
	 * @notice Calculates the remaining open amount of a quote (encrypted).
	 * @param quote The quote for which to calculate the remaining open amount.
	 * @return The remaining open amount of the quote (encrypted).
	 */
	function quoteOpenAmount(Quote storage quote) internal returns (gtUint256) {
		gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
		gtUint256 gtClosedAmount = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
		return gtQuantity.sub(gtClosedAmount);
	}

	/**
	 * @notice Gets the index of an item in an array.
	 * @param array_ The array in which to search for the item.
	 * @param item The item to find the index of.
	 * @return The index of the item in the array, or type(uint256).max if the item is not found.
	 */
	function getIndexOfItem(uint256[] storage array_, uint256 item) internal view returns (uint256) {
		for (uint256 index = 0; index < array_.length; index++) {
			if (array_[index] == item) return index;
		}
		return type(uint256).max;
	}

	/**
	 * @notice Removes an item from an array.
	 * @param array_ The array from which to remove the item.
	 * @param item The item to remove from the array.
	 */
	function removeFromArray(uint256[] storage array_, uint256 item) internal {
		uint256 index = getIndexOfItem(array_, item);
		require(index != type(uint256).max, "LibQuote: Item not Found");
		array_[index] = array_[array_.length - 1];
		array_.pop();
	}

	/**
	 * @notice Removes a quote from the pending quotes of Party A.
	 * @param quote The quote to remove from the pending quotes.
	 */
	function removeFromPartyAPendingQuotes(Quote storage quote) internal {
		removeFromArray(QuoteStorage.layout().partyAPendingQuotes[quote.partyA], quote.id);
	}

	/**
	 * @notice Removes a quote from the pending quotes of Party B.
	 * @param quote The quote to remove from the pending quotes.
	 */
	function removeFromPartyBPendingQuotes(Quote storage quote) internal {
		removeFromArray(QuoteStorage.layout().partyBPendingQuotes[quote.partyB][quote.partyA], quote.id);
	}

	/**
	 * @notice Removes a quote from both Party A's and Party B's pending quotes.
	 * @param quote The quote to remove from the pending quotes.
	 */
	function removeFromPendingQuotes(Quote storage quote) internal {
		removeFromPartyAPendingQuotes(quote);
		removeFromPartyBPendingQuotes(quote);
	}

	/**
	 * @notice Adds a quote to the open positions.
	 * @param quoteId The ID of the quote to add to the open positions.
	 */
	function addToOpenPositions(uint256 quoteId) internal {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];

		quoteLayout.partyAOpenPositions[quote.partyA].push(quote.id);
		quoteLayout.partyBOpenPositions[quote.partyB][quote.partyA].push(quote.id);

		quoteLayout.partyAPositionsIndex[quote.id] = quoteLayout.partyAPositionsCount[quote.partyA];
		quoteLayout.partyBPositionsIndex[quote.id] = quoteLayout.partyBPositionsCount[quote.partyB][quote.partyA];

		quoteLayout.partyAPositionsCount[quote.partyA] += 1;
		quoteLayout.partyBPositionsCount[quote.partyB][quote.partyA] += 1;
	}

	/**
	 * @notice Removes a quote from the open positions.
	 * @param quoteId The ID of the quote to remove from the open positions.
	 */
	function removeFromOpenPositions(uint256 quoteId) internal {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		uint256 indexOfPartyAPosition = quoteLayout.partyAPositionsIndex[quote.id];
		uint256 indexOfPartyBPosition = quoteLayout.partyBPositionsIndex[quote.id];
		uint256 lastOpenPositionIndex = quoteLayout.partyAPositionsCount[quote.partyA] - 1;
		quoteLayout.partyAOpenPositions[quote.partyA][indexOfPartyAPosition] = quoteLayout.partyAOpenPositions[quote.partyA][lastOpenPositionIndex];
		quoteLayout.partyAPositionsIndex[quoteLayout.partyAOpenPositions[quote.partyA][lastOpenPositionIndex]] = indexOfPartyAPosition;
		quoteLayout.partyAOpenPositions[quote.partyA].pop();

		lastOpenPositionIndex = quoteLayout.partyBPositionsCount[quote.partyB][quote.partyA] - 1;
		quoteLayout.partyBOpenPositions[quote.partyB][quote.partyA][indexOfPartyBPosition] = quoteLayout.partyBOpenPositions[quote.partyB][
			quote.partyA
		][lastOpenPositionIndex];
		quoteLayout.partyBPositionsIndex[quoteLayout.partyBOpenPositions[quote.partyB][quote.partyA][lastOpenPositionIndex]] = indexOfPartyBPosition;
		quoteLayout.partyBOpenPositions[quote.partyB][quote.partyA].pop();

		quoteLayout.partyAPositionsIndex[quote.id] = 0;
		quoteLayout.partyBPositionsIndex[quote.id] = 0;
	}

	/**
	 * @notice Calculates the value of a quote for Party A using encrypted values.
	 * @param gtCurrentPrice The encrypted current price of the quote.
	 * @param gtFilledAmount The encrypted filled amount of the quote.
	 * @param quote The quote for which to calculate the value.
	 * @return hasMadeProfit A boolean indicating whether Party A has made a profit.
	 * @return pnl The profit or loss value for Party A (encrypted).
	 */
	function getValueOfQuoteForPartyA(
		gtUint256 gtCurrentPrice,
		gtUint256 gtFilledAmount,
		Quote storage quote
	) internal returns (bool hasMadeProfit, gtUint256 pnl) {
		gtUint256 gtOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));
		bool isCurrentGreater = MpcCore.decrypt(gtCurrentPrice.gt(gtOpenedPrice));
		bool isLong = quote.positionType == PositionType.LONG;
		hasMadeProfit = isLong ? isCurrentGreater : !isCurrentGreater;
		pnl = isCurrentGreater 
			? gtCurrentPrice.sub(gtOpenedPrice).mul(gtFilledAmount).div(gtScaleFactor)
			: gtOpenedPrice.sub(gtCurrentPrice).mul(gtFilledAmount).div(gtScaleFactor);
	}

	/**
	 * @notice Gets the trading fee for a quote.
	 * @param quoteId The ID of the quote for which to get the trading fee.
	 * @return fee The trading fee for the quote (encrypted).
	 */
	function getTradingFee(uint256 quoteId) internal returns (gtUint256 fee) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
		gtUint256 gtTradingFee = LockedValuesOps.safeOnboard(quote.tradingFee.ciphertext);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e36));
		
		if (quote.orderType == OrderType.LIMIT) {
			gtUint256 gtRequestedOpenPrice = LockedValuesOps.safeOnboard(quote.requestedOpenPrice.ciphertext);
			fee = gtOpenAmount.mul(gtRequestedOpenPrice).mul(gtTradingFee).div(gtScaleFactor);
		} else {
			gtUint256 gtMarketPrice = LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext);
			fee = gtOpenAmount.mul(gtMarketPrice).mul(gtTradingFee).div(gtScaleFactor);
		}
	}

	/**
	 * @notice Closes a quote.
	 * @param quote The quote to close.
	 * @param gtFilledAmount The encrypted filled amount of the quote.
	 * @param gtClosedPrice The encrypted price at which the quote is closed.
	 */
	function closeQuote(Quote storage quote, gtUint256 gtFilledAmount, gtUint256 gtClosedPrice) internal {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

		// Onboard encrypted values
		gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
		GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
		
		// Check that proportional amounts are not too low
		gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
		gtBool cvaIsZero = gtLockedValues.cva.eq(gtZero);
		gtBool cvaProportionOk = gtLockedValues.cva.mul(gtFilledAmount).div(gtOpenAmount).gt(gtZero);
		require(MpcCore.decrypt(cvaIsZero.or(cvaProportionOk)), "LibQuote: Low filled amount");
		
		gtBool partyAmmIsZero = gtLockedValues.partyAmm.eq(gtZero);
		gtBool partyAmmProportionOk = gtLockedValues.partyAmm.mul(gtFilledAmount).div(gtOpenAmount).gt(gtZero);
		require(MpcCore.decrypt(partyAmmIsZero.or(partyAmmProportionOk)), "LibQuote: Low filled amount");
		
		gtBool partyBmmIsZero = gtLockedValues.partyBmm.eq(gtZero);
		gtBool partyBmmProportionOk = gtLockedValues.partyBmm.mul(gtFilledAmount).div(gtOpenAmount).gt(gtZero);
		require(MpcCore.decrypt(partyBmmIsZero.or(partyBmmProportionOk)), "LibQuote: Low filled amount");
		
		gtBool lfProportionOk = gtLockedValues.lf.mul(gtFilledAmount).div(gtOpenAmount).gt(gtZero);
		require(MpcCore.decrypt(lfProportionOk), "LibQuote: Low filled amount");
		
		// Calculate remaining locked values after partial close
		GarbledLockedValues memory gtNewLockedValues = GarbledLockedValues({
			cva: gtLockedValues.cva.sub(gtLockedValues.cva.mul(gtFilledAmount).div(gtOpenAmount)),
			lf: gtLockedValues.lf.sub(gtLockedValues.lf.mul(gtFilledAmount).div(gtOpenAmount)),
			partyAmm: gtLockedValues.partyAmm.sub(gtLockedValues.partyAmm.mul(gtFilledAmount).div(gtOpenAmount)),
			partyBmm: gtLockedValues.partyBmm.sub(gtLockedValues.partyBmm.mul(gtFilledAmount).div(gtOpenAmount))
		});
		
		// Update storage: subtract old quote values, add new values
		GarbledLockedValues memory gtResultA = accountLayout.lockedBalances[quote.partyA].subQuoteGarbled(quote).add(gtNewLockedValues);
		GarbledLockedValues memory gtResultB = accountLayout.partyBLockedBalances[quote.partyB][quote.partyA].subQuoteGarbled(quote).add(gtNewLockedValues);
		
		accountLayout.lockedBalances[quote.partyA] = gtResultA.offBoard(quote.partyA);
		accountLayout.partyBLockedBalances[quote.partyB][quote.partyA] = gtResultB.offBoard(quote.partyA);
		quote.lockedValues = gtNewLockedValues.offBoard(quote.partyA);

		// Check if this is the final close and remaining value is acceptable
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);
		gtBool isFinalClose = gtOpenAmount.eq(gtQuantityToClose);
		if (MpcCore.decrypt(isFinalClose)) {
			GarbledLockedValues memory gtRemainingLocked = quote.lockedValues.onBoard();
			gtUint256 gtTotalForPartyA = gtRemainingLocked.totalForPartyA();
			gtUint256 gtMinValue = MpcCore.setPublic256(symbolLayout.symbols[quote.symbolId].minAcceptableQuoteValue);
			gtBool isZero = gtTotalForPartyA.eq(gtZero);
			gtBool isAboveMin = gtTotalForPartyA.ge(gtMinValue);
			require(MpcCore.decrypt(isZero.or(isAboveMin)), "LibQuote: Remaining quote value is low");
		}

		// Calculate PNL with encrypted values
		(bool hasMadeProfit, gtUint256 gtPnl) = LibQuote.getValueOfQuoteForPartyA(gtClosedPrice, gtFilledAmount, quote);

		if (hasMadeProfit) {
			// Check PartyB has sufficient balance using encrypted comparison
			gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA].ciphertext);
			gtBool gtSufficientBalance = gtPartyBBalance.ge(gtPnl);
			require(MpcCore.decrypt(gtSufficientBalance), "LibQuote: PartyA should first exit its positions that are incurring losses");
			
			// Update PartyA balance
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
			gtUint256 gtNewPartyABalance = gtPartyABalance.add(gtPnl);
			accountLayout.allocatedBalances[quote.partyA] = MpcCore.offBoardCombined(gtNewPartyABalance, LibAccount.getUserEncryptionAddress(quote.partyA));
			
			// Update PartyB balance
			gtUint256 gtNewPartyBBalance = gtPartyBBalance.sub(gtPnl);
			accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA] = MpcCore.offBoardCombined(gtNewPartyBBalance, LibAccount.getUserEncryptionAddress(quote.partyB));
			
			// Emit encrypted events for both parties
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtPnl, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(quote.partyA, partyAAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
			
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
			ctUint256 memory partyBAmount = MpcCore.offBoardToUser(gtPnl, partyBEncryptionAddress);
			emit SharedEvents.BalanceChangePartyB(quote.partyB, quote.partyA, partyBAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
		} else {
			// Check PartyA has sufficient balance using encrypted comparison
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
			gtBool gtSufficientBalance = gtPartyABalance.ge(gtPnl);
			require(MpcCore.decrypt(gtSufficientBalance), "LibQuote: PartyA should first exit its positions that are currently in profit.");
			
			// Update PartyA balance
			gtUint256 gtNewPartyABalance = gtPartyABalance.sub(gtPnl);
			accountLayout.allocatedBalances[quote.partyA] = MpcCore.offBoardCombined(gtNewPartyABalance, LibAccount.getUserEncryptionAddress(quote.partyA));
			
			// Update PartyB balance
			gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA].ciphertext);
			gtUint256 gtNewPartyBBalance = gtPartyBBalance.add(gtPnl);
			accountLayout.partyBAllocatedBalances[quote.partyB][quote.partyA] = MpcCore.offBoardCombined(gtNewPartyBBalance, LibAccount.getUserEncryptionAddress(quote.partyB));
			
			// Emit encrypted events for both parties
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtPnl, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(quote.partyA, partyAAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
			
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
			ctUint256 memory partyBAmount = MpcCore.offBoardToUser(gtPnl, partyBEncryptionAddress);
			emit SharedEvents.BalanceChangePartyB(quote.partyB, quote.partyA, partyBAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
		}

		// Update avgClosedPrice: (avgClosedPrice * closedAmount + filledAmount * closedPrice) / (closedAmount + filledAmount)
		gtUint256 gtAvgClosedPrice = LockedValuesOps.safeOnboard(quote.avgClosedPrice.ciphertext);
		gtUint256 gtClosedAmount = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
		gtUint256 gtNewAvgClosedPrice = gtAvgClosedPrice.mul(gtClosedAmount).add(gtFilledAmount.mul(gtClosedPrice)).div(gtClosedAmount.add(gtFilledAmount));
		quote.avgClosedPrice = MpcCore.offBoardCombined(gtNewAvgClosedPrice, LibAccount.getUserEncryptionAddress(quote.partyA));

		// Update closedAmount and quantityToClose
		gtUint256 gtNewClosedAmount = gtClosedAmount.add(gtFilledAmount);
		quote.closedAmount = MpcCore.offBoardCombined(gtNewClosedAmount, LibAccount.getUserEncryptionAddress(quote.partyA));
		
		gtUint256 gtNewQuantityToClose = gtQuantityToClose.sub(gtFilledAmount);
		quote.quantityToClose = MpcCore.offBoardCombined(gtNewQuantityToClose, LibAccount.getUserEncryptionAddress(quote.partyA));

		// Check if quote is fully closed
		gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
		gtBool isFullyClosed = gtNewClosedAmount.eq(gtQuantity);
		if (MpcCore.decrypt(isFullyClosed)) {
			quote.statusModifyTimestamp = block.timestamp;
			quote.quoteStatus = QuoteStatus.CLOSED;
			quote.requestedClosePrice = MpcCore.offBoardCombined(gtZero, LibAccount.getUserEncryptionAddress(quote.partyA));
			removeFromOpenPositions(quote.id);
			quoteLayout.partyAPositionsCount[quote.partyA] -= 1;
			quoteLayout.partyBPositionsCount[quote.partyB][quote.partyA] -= 1;
		} else if (quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING || MpcCore.decrypt(gtNewQuantityToClose.eq(gtZero))) {
			quote.quoteStatus = QuoteStatus.OPENED;
			quote.statusModifyTimestamp = block.timestamp;
			quote.requestedClosePrice = MpcCore.offBoardCombined(gtZero, LibAccount.getUserEncryptionAddress(quote.partyA));
			quote.quantityToClose = MpcCore.offBoardCombined(gtZero, quote.partyA);
		}
	}

	/**
	 * @notice Expires a quote.
	 * @param quoteId The ID of the quote to expire.
	 * @return result The resulting status of the quote after expiration.
	 */
	function expireQuote(uint256 quoteId) internal returns (QuoteStatus result) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		Quote storage quote = quoteLayout.quotes[quoteId];
		require(block.timestamp > quote.deadline, "LibQuote: Quote isn't expired");
		require(
			quote.quoteStatus == QuoteStatus.PENDING ||
				quote.quoteStatus == QuoteStatus.CANCEL_PENDING ||
				quote.quoteStatus == QuoteStatus.LOCKED ||
				quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
				quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
			"LibQuote: Invalid state"
		);
		require(!MAStorage.layout().liquidationStatus[quote.partyA], "LibQuote: PartyA isn't solvent");
		require(!MAStorage.layout().partyBLiquidationStatus[quote.partyB][quote.partyA], "LibQuote: PartyB isn't solvent");
		if (quote.quoteStatus == QuoteStatus.PENDING || quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING) {
			quote.statusModifyTimestamp = block.timestamp;
			accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote, LibAccount.getUserEncryptionAddress(quote.partyA));

			// send trading Fee back to partyA
			gtUint256 gtFee = LibQuote.getTradingFee(quote.id);
			
			// Update PartyA balance with encrypted operations
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[quote.partyA].ciphertext);
			gtUint256 gtNewPartyABalance = gtPartyABalance.add(gtFee);
			accountLayout.allocatedBalances[quote.partyA] = MpcCore.offBoardCombined(gtNewPartyABalance, LibAccount.getUserEncryptionAddress(quote.partyA));
			
			// Emit encrypted event for PartyA
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtFee, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(quote.partyA, partyAAmount, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);

			removeFromPartyAPendingQuotes(quote);
			if (quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING) {
				accountLayout.partyBPendingLockedBalances[quote.partyB][quote.partyA].subQuote(quote, LibAccount.getUserEncryptionAddress(quote.partyB));
				removeFromPartyBPendingQuotes(quote);
			}
			quote.quoteStatus = QuoteStatus.EXPIRED;
			result = QuoteStatus.EXPIRED;
		} else if (quote.quoteStatus == QuoteStatus.CLOSE_PENDING || quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING) {
			quote.statusModifyTimestamp = block.timestamp;
			gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
			quote.requestedClosePrice = MpcCore.offBoardCombined(gtZero, LibAccount.getUserEncryptionAddress(quote.partyA));
			quote.quantityToClose = MpcCore.offBoardCombined(gtZero, LibAccount.getUserEncryptionAddress(quote.partyA));
			quote.quoteStatus = QuoteStatus.OPENED;
			result = QuoteStatus.OPENED;
		}
	}
}
