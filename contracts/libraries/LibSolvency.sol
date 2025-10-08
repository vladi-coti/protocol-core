// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/QuoteStorage.sol";
import "./LibAccount.sol";
import "./LibQuote.sol";
import "./LibLockedValues.sol";

library LibSolvency {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	/**
	 * @dev Checks whether both parties (Party A and Party B) will remain solvent after opening positions for given quotes.
	 * @param quoteIds The ID of the quotes for which the positions is being opened.
	 * @param filledAmounts The amount of the quotes that will be filled by opening the positions.
	 * @param marketPrices The market price of positions that will be opened.
	 * @param upnlPartyB The upnl of partyB
	 * @param upnlPartyA The upnl of partyA
	 * @param partyB Address of partyB
	 * @param partyA Address of partyA
	 * @return A boolean indicating whether both parties remain solvent after opening the position.
	 */
	function isSolventAfterOpenPosition(
		uint256[] memory quoteIds,
		uint256[] memory filledAmounts,
		uint256[] memory marketPrices,
		int256 upnlPartyB,
		int256 upnlPartyA,
		address partyB,
		address partyA
	) internal returns (bool) {
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlPartyB, partyB, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			upnlPartyA,
			AccountStorage.layout().allocatedBalances[partyA],
			partyA
		);
		int256 partyBAvailableBalance = MpcCore.decrypt(gtPartyBAvailableBalance);
		int256 partyAAvailableBalance = MpcCore.decrypt(gtPartyAAvailableBalance);
		
		for (uint8 i = 0; i < quoteIds.length; i++) {
			uint256 quoteId = quoteIds[i];
			uint256 filledAmount = filledAmounts[i];
			uint256 marketPrice = marketPrices[i];
			Quote storage quote = QuoteStorage.layout().quotes[quoteId];
			
			// Decrypt openedPrice for comparison
			gtUint256 gtOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
			uint256 openedPrice = MpcCore.decrypt(gtOpenedPrice);
			
			if (quote.positionType == PositionType.LONG) {
				if (openedPrice >= marketPrice) {
					uint256 diff = (filledAmount * (openedPrice - marketPrice)) / 1e18;
					partyAAvailableBalance -= int256(diff);
					partyBAvailableBalance += int256(diff);
				} else {
					uint256 diff = (filledAmount * (marketPrice - openedPrice)) / 1e18;
					partyBAvailableBalance -= int256(diff);
					partyAAvailableBalance += int256(diff);
				}
			} else if (quote.positionType == PositionType.SHORT) {
				if (openedPrice >= marketPrice) {
					uint256 diff = (filledAmount * (openedPrice - marketPrice)) / 1e18;
					partyBAvailableBalance -= int256(diff);
					partyAAvailableBalance += int256(diff);
				} else {
					uint256 diff = (filledAmount * (marketPrice - openedPrice)) / 1e18;
					partyAAvailableBalance -= int256(diff);
					partyBAvailableBalance += int256(diff);
				}
			}
		}
		require(partyBAvailableBalance >= 0 && partyAAvailableBalance >= 0, "LibSolvency: Available balance is lower than zero");
		return true;
	}

	/**
	 * @dev Calculates the available balances for Party A and Party B after closing positions for given quotes.
	 * @param quoteIds The ID of the quotes for which the position is being closed.
	 * @param filledAmounts The amount of the quotes that will be filled by closing the position.
	 * @param closedPrices The price at which the positions will be closed.
	 * @param marketPrices The market price of positions that will be closed.
	 * @param upnlPartyB The upnl of partyB
	 * @param upnlPartyA The upnl of partyA
	 * @param partyB Address of partyB
	 * @param partyA Address of partyA
	 * @return partyBAvailableBalance The available balance for Party B after closing the position.
	 * @return partyAAvailableBalance The available balance for Party A after closing the position.
	 */
	function getAvailableBalanceAfterClosePosition(
		uint256[] memory quoteIds,
		uint256[] memory filledAmounts,
		uint256[] memory closedPrices,
		uint256[] memory marketPrices,
		int256 upnlPartyB,
		int256 upnlPartyA,
		address partyB,
		address partyA
	) internal returns (int256 partyBAvailableBalance, int256 partyAAvailableBalance) {
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlPartyB, partyB, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			upnlPartyA,
			AccountStorage.layout().allocatedBalances[partyA],
			partyA
		);
		partyBAvailableBalance = MpcCore.decrypt(gtPartyBAvailableBalance);
		partyAAvailableBalance = MpcCore.decrypt(gtPartyAAvailableBalance);
		
		for (uint8 i = 0; i < quoteIds.length; i++) {
			uint256 quoteId = quoteIds[i];
			uint256 filledAmount = filledAmounts[i];
			uint256 closedPrice = closedPrices[i];
			uint256 marketPrice = marketPrices[i];
			Quote storage quote = QuoteStorage.layout().quotes[quoteId];
			
			// Calculate unlocked amount with encrypted values
			GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
			gtUint256 gtCvaLf = gtLockedValues.cva.add(gtLockedValues.lf);
			gtUint256 gtFilledAmount = MpcCore.setPublic256(filledAmount);
			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			gtUint256 gtUnlockedAmount = gtFilledAmount.mul(gtCvaLf).div(gtQuoteOpenAmount);
			uint256 unlockedAmount = MpcCore.decrypt(gtUnlockedAmount);

			partyBAvailableBalance += int256(unlockedAmount);

			partyAAvailableBalance += int256(unlockedAmount);

			if (quote.positionType == PositionType.LONG) {
				if (closedPrice >= marketPrice) {
					uint256 diff = (filledAmount * (closedPrice - marketPrice)) / 1e18;
					partyBAvailableBalance -= int256(diff);
					partyAAvailableBalance += int256(diff);
				} else {
					uint256 diff = (filledAmount * (marketPrice - closedPrice)) / 1e18;
					partyBAvailableBalance += int256(diff);
					partyAAvailableBalance -= int256(diff);
				}
			} else if (quote.positionType == PositionType.SHORT) {
				if (closedPrice <= marketPrice) {
					uint256 diff = (filledAmount * (marketPrice - closedPrice)) / 1e18;
					partyBAvailableBalance -= int256(diff);
					partyAAvailableBalance += int256(diff);
				} else {
					uint256 diff = (filledAmount * (closedPrice - marketPrice)) / 1e18;
					partyBAvailableBalance += int256(diff);
					partyAAvailableBalance -= int256(diff);
				}
			}
		}
	}

	/**
	 * @dev Checks whether both parties (Party A and Party B) will remain solvent after closing positions for given quotes.
	 * @param quoteIds The ID of the quotes for which the position is being closed.
	 * @param filledAmounts The amount of the quotes that will be filled by closing the position.
	 * @param closedPrices The price at which the positions will be closed.
	 * @param marketPrices The market price of positions that will be closed.
	 * @param upnlPartyB The upnl of partyB
	 * @param upnlPartyA The upnl of partyA
	 * @param partyB Address of partyB
	 * @param partyA Address of partyA
	 * @return A boolean indicating whether both parties remain solvent after closing the position.
	 */
	function isSolventAfterClosePosition(
		uint256[] memory quoteIds,
		uint256[] memory filledAmounts,
		uint256[] memory closedPrices,
		uint256[] memory marketPrices,
		int256 upnlPartyB,
		int256 upnlPartyA,
		address partyB,
		address partyA
	) internal returns (bool) {
		(int256 partyBAvailableBalance, int256 partyAAvailableBalance) = getAvailableBalanceAfterClosePosition(
			quoteIds,
			filledAmounts,
			closedPrices,
			marketPrices,
			upnlPartyB,
			upnlPartyA,
			partyB,
			partyA
		);

		require(partyBAvailableBalance >= 0 && partyAAvailableBalance >= 0, "LibSolvency: Available balance is lower than zero");
		return true;
	}
}
