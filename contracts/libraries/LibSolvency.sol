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
	 * @param quoteId The ID of the quote for which the position is being opened.
	 * @param gtFilledAmount The encrypted amount of the quote that will be filled by opening the position.
	 * @param gtOpenedPrice The encrypted opened price of the position.
	 * @param marketPrice The market price of the position that will be opened.
	 * @param upnlPartyB The upnl of partyB
	 * @param upnlPartyA The upnl of partyA
	 * @param partyB Address of partyB
	 * @param partyA Address of partyA
	 * @return A boolean indicating whether both parties remain solvent after opening the position.
	 */
	function isSolventAfterOpenPosition(
		uint256 quoteId,
		gtUint256 gtFilledAmount,
		gtUint256 gtOpenedPrice,
		uint256 marketPrice,
		int256 upnlPartyB,
		int256 upnlPartyA,
		address partyB,
		address partyA
	) internal returns (bool) {
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlPartyB, partyB, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			upnlPartyA,
			partyA
		);
		
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		
		// Convert marketPrice to encrypted value for comparison
		gtUint256 gtMarketPrice = MpcCore.setPublic256(marketPrice);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));
		gtBool gtOpenedPriceGteMarket = gtOpenedPrice.ge(gtMarketPrice);
		
		if (quote.positionType == PositionType.LONG) {
			// Check if openedPrice >= marketPrice using MPC comparison
			if(MpcCore.decrypt(gtOpenedPriceGteMarket)) {
				gtInt256 gtDiff = gtFilledAmount.mul(gtOpenedPrice.sub(gtMarketPrice)).div(gtScaleFactor).toSigned();
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtDiff);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.sub(gtDiff);
			} else {
				gtInt256 gtDiff = gtFilledAmount.mul(gtMarketPrice.sub(gtOpenedPrice)).div(gtScaleFactor).toSigned();
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.sub(gtDiff);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtDiff);
			}
		} else {
			if(MpcCore.decrypt(gtOpenedPriceGteMarket)) {
				gtInt256 gtDiff = gtFilledAmount.mul(gtOpenedPrice.sub(gtMarketPrice)).div(gtScaleFactor).toSigned();
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.sub(gtDiff);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtDiff);
			} else {
				gtInt256 gtDiff = gtFilledAmount.mul(gtMarketPrice.sub(gtOpenedPrice)).div(gtScaleFactor).toSigned();
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtDiff);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.sub(gtDiff);
			}
		}
		
		// Check solvency using encrypted comparisons - decrypt only the boolean results
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		gtBool gtPartyBSolvent = gtPartyBAvailableBalance.ge(gtZero);
		gtBool gtPartyASolvent = gtPartyAAvailableBalance.ge(gtZero);
		
		require(MpcCore.decrypt(gtPartyBSolvent.and(gtPartyASolvent)), "LibSolvency: Available balance is lower than zero");
		return true;
	}

	/**
	 * @dev Calculates the available balances for Party A and Party B after closing positions for given quotes.
	 * @param quoteIds The ID of the quotes for which the position is being closed.
	 * @param gtFilledAmounts The encrypted amounts of the quotes that will be filled by closing the position.
	 * @param gtClosedPrices The encrypted prices at which the positions will be closed.
	 * @param marketPrices The market price of positions that will be closed.
	 * @param upnlPartyB The upnl of partyB
	 * @param upnlPartyA The upnl of partyA
	 * @param partyB Address of partyB
	 * @param partyA Address of partyA
	 * @return gtPartyBAvailableBalance The available balance for Party B after closing the position (encrypted).
	 * @return gtPartyAAvailableBalance The available balance for Party A after closing the position (encrypted).
	 */
	function getAvailableBalanceAfterClosePosition(
		uint256[] memory quoteIds,
		gtUint256[] memory gtFilledAmounts,
		gtUint256[] memory gtClosedPrices,
		uint256[] memory marketPrices,
		int256 upnlPartyB,
		int256 upnlPartyA,
		address partyB,
		address partyA
	) internal returns (gtInt256, gtInt256) {
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlPartyB, partyB, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			upnlPartyA,
			partyA
		);
		
		for (uint8 i = 0; i < quoteIds.length; i++) {
			uint256 quoteId = quoteIds[i];
			gtUint256 gtFilledAmount = gtFilledAmounts[i];
			gtUint256 gtClosedPrice = gtClosedPrices[i];
			uint256 marketPrice = marketPrices[i];
			Quote storage quote = QuoteStorage.layout().quotes[quoteId];
			
			// Calculate unlocked amount with encrypted values
			GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
			gtUint256 gtCvaLf = gtLockedValues.cva.add(gtLockedValues.lf);
			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			gtUint256 gtUnlockedAmount = gtFilledAmount.mul(gtCvaLf).div(gtQuoteOpenAmount);

			// Add unlocked amount to both parties (this is always positive)
			gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtUnlockedAmount.toSigned());
			gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtUnlockedAmount.toSigned());

			// Convert market price to encrypted value for comparison
			gtUint256 gtMarketPrice = MpcCore.setPublic256(marketPrice);
			gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));

			if (quote.positionType == PositionType.LONG) {
				gtBool gtClosedPriceGteMarket = gtClosedPrice.ge(gtMarketPrice);

				gtUint256 gtPriceDiff = MpcCore.mux(gtClosedPriceGteMarket, gtMarketPrice.sub(gtClosedPrice), gtClosedPrice.sub(gtMarketPrice));
				gtInt256 gtDiff = gtFilledAmount.mul(gtPriceDiff).div(gtScaleFactor).toSigned();
				
				gtPartyBAvailableBalance = MpcCore.mux(gtClosedPriceGteMarket, gtPartyBAvailableBalance.add(gtDiff), gtPartyBAvailableBalance.sub(gtDiff));
				gtPartyAAvailableBalance = MpcCore.mux(gtClosedPriceGteMarket, gtPartyAAvailableBalance.sub(gtDiff), gtPartyAAvailableBalance.add(gtDiff));
			} else if (quote.positionType == PositionType.SHORT) {
				gtBool gtClosedPriceLteMarket = gtClosedPrice.le(gtMarketPrice);

				gtUint256 gtPriceDiff = MpcCore.mux(gtClosedPriceLteMarket, gtClosedPrice.sub(gtMarketPrice), gtMarketPrice.sub(gtClosedPrice));
				gtInt256 gtDiff = gtFilledAmount.mul(gtPriceDiff).div(gtScaleFactor).toSigned();
				
				gtPartyBAvailableBalance = MpcCore.mux(gtClosedPriceLteMarket, gtPartyBAvailableBalance.add(gtDiff), gtPartyBAvailableBalance.sub(gtDiff));
				gtPartyAAvailableBalance = MpcCore.mux(gtClosedPriceLteMarket, gtPartyAAvailableBalance.sub(gtDiff), gtPartyAAvailableBalance.add(gtDiff));
			}
		}
		
		return (gtPartyBAvailableBalance, gtPartyAAvailableBalance);
	}

	/**
	 * @dev Checks whether both parties (Party A and Party B) will remain solvent after closing positions for given quotes.
	 * @param quoteIds The ID of the quotes for which the position is being closed.
	 * @param gtFilledAmounts The encrypted amounts of the quotes that will be filled by closing the position.
	 * @param gtClosedPrices The encrypted prices at which the positions will be closed.
	 * @param marketPrices The market price of positions that will be closed.
	 * @param upnlPartyB The upnl of partyB
	 * @param upnlPartyA The upnl of partyA
	 * @param partyB Address of partyB
	 * @param partyA Address of partyA
	 * @return A boolean indicating whether both parties remain solvent after closing the position.
	 */
	function isSolventAfterClosePosition(
		uint256[] memory quoteIds,
		gtUint256[] memory gtFilledAmounts,
		gtUint256[] memory gtClosedPrices,
		uint256[] memory marketPrices,
		int256 upnlPartyB,
		int256 upnlPartyA,
		address partyB,
		address partyA
	) internal returns (bool) {
		(gtInt256 gtPartyBAvailableBalance, gtInt256 gtPartyAAvailableBalance) = getAvailableBalanceAfterClosePosition(
			quoteIds,
			gtFilledAmounts,
			gtClosedPrices,
			marketPrices,
			upnlPartyB,
			upnlPartyA,
			partyB,
			partyA
		);

		// Check solvency using encrypted comparisons - decrypt only the boolean results
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		gtBool gtPartyBSolvent = gtPartyBAvailableBalance.ge(gtZero);
		gtBool gtPartyASolvent = gtPartyAAvailableBalance.ge(gtZero);
		
		require(MpcCore.decrypt(gtPartyBSolvent), "LibSolvency: Available partyB balance is lower than zero");
		require(MpcCore.decrypt(gtPartyASolvent), "LibSolvency: Available partyA balance is lower than zero");
		return true;
	}
}
