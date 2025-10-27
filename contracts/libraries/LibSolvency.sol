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
		
		if (quote.positionType == PositionType.LONG) {
			// Calculate encrypted difference: filledAmount * (openedPrice - marketPrice) / 1e18
			gtUint256 gtDiff = gtFilledAmount.mul(gtOpenedPrice.sub(gtMarketPrice)).div(gtScaleFactor);
			
			// Check if openedPrice >= marketPrice using MPC comparison
			gtBool gtOpenedPriceGteMarket = gtOpenedPrice.ge(gtMarketPrice);
			
			// Calculate balance adjustments using MPC mux (conditional selection)
			gtInt256 gtPartyAAdjustment = MpcCore.mux(
				gtOpenedPriceGteMarket,
				MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned()), // openedPrice >= marketPrice: PartyA loses, PartyB gains
				gtDiff.toSigned()        // openedPrice < marketPrice: PartyA gains, PartyB loses
			);
			gtInt256 gtPartyBAdjustment = MpcCore.mux(
				gtOpenedPriceGteMarket,
				gtDiff.toSigned(),       // openedPrice >= marketPrice: PartyB gains, PartyA loses
				MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned())  // openedPrice < marketPrice: PartyB loses, PartyA gains
			);
			
			gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtPartyAAdjustment);
			gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtPartyBAdjustment);
		} else if (quote.positionType == PositionType.SHORT) {
			// Calculate encrypted difference: filledAmount * (openedPrice - marketPrice) / 1e18
			gtUint256 gtDiff = gtFilledAmount.mul(gtOpenedPrice.sub(gtMarketPrice)).div(gtScaleFactor);
			
			// Check if openedPrice >= marketPrice using MPC comparison
			gtBool gtOpenedPriceGteMarket = gtOpenedPrice.ge(gtMarketPrice);
			
			// Calculate balance adjustments using MPC mux (conditional selection)
			gtInt256 gtPartyAAdjustment = MpcCore.mux(
				gtOpenedPriceGteMarket,
				gtDiff.toSigned(),       // openedPrice >= marketPrice: PartyA gains, PartyB loses
				MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned())  // openedPrice < marketPrice: PartyA loses, PartyB gains
			);
			gtInt256 gtPartyBAdjustment = MpcCore.mux(
				gtOpenedPriceGteMarket,
				MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned()), // openedPrice >= marketPrice: PartyB loses, PartyA gains
				gtDiff.toSigned()        // openedPrice < marketPrice: PartyB gains, PartyA loses
			);
			
			gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtPartyAAdjustment);
			gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtPartyBAdjustment);
		}
		
		// Only decrypt the final balance checks
		int256 partyBAvailableBalance = MpcCore.decrypt(gtPartyBAvailableBalance);
		int256 partyAAvailableBalance = MpcCore.decrypt(gtPartyAAvailableBalance);
		
		require(partyBAvailableBalance >= 0 && partyAAvailableBalance >= 0, "LibSolvency: Available balance is lower than zero");
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
				// Calculate encrypted difference: filledAmount * (closedPrice - marketPrice) / 1e18
				gtUint256 gtDiff = gtFilledAmount.mul(gtClosedPrice.sub(gtMarketPrice)).div(gtScaleFactor);
				
				// Check if closedPrice >= marketPrice using MPC comparison
				gtBool gtClosedPriceGteMarket = gtClosedPrice.ge(gtMarketPrice);
				
				// Calculate balance adjustments using MPC mux (conditional selection)
				gtInt256 gtPartyAAdjustment = MpcCore.mux(
					gtClosedPriceGteMarket,
					gtDiff.toSigned(),       // closedPrice >= marketPrice: PartyA gains, PartyB loses
					MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned())  // closedPrice < marketPrice: PartyA loses, PartyB gains
				);
				gtInt256 gtPartyBAdjustment = MpcCore.mux(
					gtClosedPriceGteMarket,
					MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned()), // closedPrice >= marketPrice: PartyB loses, PartyA gains
					gtDiff.toSigned()        // closedPrice < marketPrice: PartyB gains, PartyA loses
				);
				
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtPartyAAdjustment);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtPartyBAdjustment);
			} else if (quote.positionType == PositionType.SHORT) {
				// Calculate encrypted difference: filledAmount * (closedPrice - marketPrice) / 1e18
				gtUint256 gtDiff = gtFilledAmount.mul(gtClosedPrice.sub(gtMarketPrice)).div(gtScaleFactor);
				
				// Check if closedPrice <= marketPrice using MPC comparison
				gtBool gtClosedPriceLteMarket = gtClosedPrice.le(gtMarketPrice);
				
				// Calculate balance adjustments using MPC mux (conditional selection)
				gtInt256 gtPartyAAdjustment = MpcCore.mux(
					gtClosedPriceLteMarket,
					gtDiff.toSigned(),       // closedPrice <= marketPrice: PartyA gains, PartyB loses
					MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned())  // closedPrice > marketPrice: PartyA loses, PartyB gains
				);
				gtInt256 gtPartyBAdjustment = MpcCore.mux(
					gtClosedPriceLteMarket,
					MpcCore.setPublic256(uint256(0)).toSigned().sub(gtDiff.toSigned()), // closedPrice <= marketPrice: PartyB loses, PartyA gains
					gtDiff.toSigned()        // closedPrice > marketPrice: PartyB gains, PartyA loses
				);
				
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtPartyAAdjustment);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtPartyBAdjustment);
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

		// Check solvency using encrypted comparisons
		gtInt256 gtZero = MpcCore.setPublic256(uint256(0)).toSigned();
		gtBool gtPartyBSolvent = gtPartyBAvailableBalance.ge(gtZero);
		gtBool gtPartyASolvent = gtPartyAAvailableBalance.ge(gtZero);
		gtBool bothSolvent = gtPartyBSolvent.and(gtPartyASolvent);
		
		require(MpcCore.decrypt(bothSolvent), "LibSolvency: Available balance is lower than zero");
		return true;
	}
}
