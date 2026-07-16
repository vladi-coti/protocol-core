// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/QuoteStorage.sol";
import "./LibAccount.sol";
import "./LibEncryption.sol";
import "./LibQuote.sol";
import "./LibLockedValues.sol";

library LibSolvency {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function isSolventAfterOpenPosition(
		uint256 quoteId,
		gtUint256 gtFilledAmount,
		gtUint256 gtOpenedPrice,
		uint256 marketPrice,
		gtInt256 gtUpnlPartyB,
		gtInt256 gtUpnlPartyA,
		address partyB,
		address partyA
	) internal returns (bool) {
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(gtUpnlPartyB, partyB, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(gtUpnlPartyA, partyA);

		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		gtUint256 gtMarketPrice = MpcCore.setPublic256(marketPrice);
		gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));
		gtBool gtOpenedPriceGteMarket = gtOpenedPrice.ge(gtMarketPrice);
		gtUint256 gtPriceDiff = MpcCore.max(gtOpenedPrice, gtMarketPrice).checkedSub(MpcCore.min(gtOpenedPrice, gtMarketPrice));
		gtInt256 gtDiff = LibEncryption.toNonNegativeSigned(gtFilledAmount.checkedMul(gtPriceDiff).div(gtScaleFactor));

		if (quote.positionType == PositionType.LONG) {
			gtPartyAAvailableBalance = MpcCore.mux(
				gtOpenedPriceGteMarket,
				gtPartyAAvailableBalance.checkedAdd(gtDiff),
				gtPartyAAvailableBalance.checkedSub(gtDiff)
			);
			gtPartyBAvailableBalance = MpcCore.mux(
				gtOpenedPriceGteMarket,
				gtPartyBAvailableBalance.checkedSub(gtDiff),
				gtPartyBAvailableBalance.checkedAdd(gtDiff)
			);
		} else {
			gtPartyAAvailableBalance = MpcCore.mux(
				gtOpenedPriceGteMarket,
				gtPartyAAvailableBalance.checkedSub(gtDiff),
				gtPartyAAvailableBalance.checkedAdd(gtDiff)
			);
			gtPartyBAvailableBalance = MpcCore.mux(
				gtOpenedPriceGteMarket,
				gtPartyBAvailableBalance.checkedAdd(gtDiff),
				gtPartyBAvailableBalance.checkedSub(gtDiff)
			);
		}

		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtPartyBAvailableBalance.ge(gtZero).and(gtPartyAAvailableBalance.ge(gtZero))), "LibSolvency: Available balance is lower than zero");
		return true;
	}

	function getAvailableBalanceAfterClosePosition(
		uint256[] memory quoteIds,
		gtUint256[] memory gtFilledAmounts,
		gtUint256[] memory gtClosedPrices,
		uint256[] memory marketPrices,
		gtInt256 gtUpnlPartyB,
		gtInt256 gtUpnlPartyA,
		address partyB,
		address partyA
	) internal returns (gtInt256 gtPartyBAvailableBalance, gtInt256 gtPartyAAvailableBalance) {
		(gtPartyBAvailableBalance, gtPartyAAvailableBalance,) = getAvailableBalanceAndPartyBUpnlAfterClosePosition(
			quoteIds,
			gtFilledAmounts,
			gtClosedPrices,
			marketPrices,
			gtUpnlPartyB,
			gtUpnlPartyA,
			partyB,
			partyA
		);
	}

	function getAvailableBalanceAndPartyBUpnlAfterClosePosition(
		uint256[] memory quoteIds,
		gtUint256[] memory gtFilledAmounts,
		gtUint256[] memory gtClosedPrices,
		uint256[] memory marketPrices,
		gtInt256 gtUpnlPartyB,
		gtInt256 gtUpnlPartyA,
		address partyB,
		address partyA
	) internal returns (gtInt256, gtInt256, gtInt256) {
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(gtUpnlPartyB, partyB, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(gtUpnlPartyA, partyA);
		gtInt256 gtPartyBUpnlAfterClose = gtUpnlPartyB;
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));

		for (uint8 i = 0; i < quoteIds.length; i++) {
			uint256 quoteId = quoteIds[i];
			gtUint256 gtFilledAmount = gtFilledAmounts[i];
			gtUint256 gtClosedPrice = gtClosedPrices[i];
			uint256 marketPrice = marketPrices[i];
			Quote storage quote = QuoteStorage.layout().quotes[quoteId];

			GarbledLockedValues memory gtLockedValues = quote.lockedValues.onBoard();
			gtUint256 gtCvaLf = gtLockedValues.cva.checkedAdd(gtLockedValues.lf);
			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			gtUint256 gtUnlockedAmount = gtFilledAmount.checkedMul(gtCvaLf).div(gtQuoteOpenAmount);

			gtPartyBAvailableBalance = gtPartyBAvailableBalance.checkedAdd(LibEncryption.toNonNegativeSigned(gtUnlockedAmount));
			gtPartyAAvailableBalance = gtPartyAAvailableBalance.checkedAdd(LibEncryption.toNonNegativeSigned(gtUnlockedAmount));

			gtUint256 gtMarketPrice = MpcCore.setPublic256(marketPrice);
			gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));

			if (quote.positionType == PositionType.LONG) {
				gtBool gtClosedPriceGteMarket = gtClosedPrice.ge(gtMarketPrice);
				gtUint256 gtPriceDiff = MpcCore.max(gtClosedPrice, gtMarketPrice).checkedSub(MpcCore.min(gtClosedPrice, gtMarketPrice));
				gtInt256 gtDiff = LibEncryption.toNonNegativeSigned(gtFilledAmount.checkedMul(gtPriceDiff).div(gtScaleFactor));
				gtInt256 gtPartyBDelta = MpcCore.mux(gtClosedPriceGteMarket, gtDiff, gtZero.checkedSub(gtDiff));

				gtPartyBAvailableBalance = gtPartyBAvailableBalance.checkedAdd(gtPartyBDelta);
				gtPartyAAvailableBalance = MpcCore.mux(gtClosedPriceGteMarket, gtPartyAAvailableBalance.checkedSub(gtDiff), gtPartyAAvailableBalance.checkedAdd(gtDiff));
				gtPartyBUpnlAfterClose = gtPartyBUpnlAfterClose.checkedAdd(gtPartyBDelta);
			} else if (quote.positionType == PositionType.SHORT) {
				gtBool gtClosedPriceLteMarket = gtClosedPrice.le(gtMarketPrice);
				gtUint256 gtPriceDiff = MpcCore.max(gtClosedPrice, gtMarketPrice).checkedSub(MpcCore.min(gtClosedPrice, gtMarketPrice));
				gtInt256 gtDiff = LibEncryption.toNonNegativeSigned(gtFilledAmount.checkedMul(gtPriceDiff).div(gtScaleFactor));
				gtInt256 gtPartyBDelta = MpcCore.mux(gtClosedPriceLteMarket, gtDiff, gtZero.checkedSub(gtDiff));

				gtPartyBAvailableBalance = gtPartyBAvailableBalance.checkedAdd(gtPartyBDelta);
				gtPartyAAvailableBalance = MpcCore.mux(gtClosedPriceLteMarket, gtPartyAAvailableBalance.checkedSub(gtDiff), gtPartyAAvailableBalance.checkedAdd(gtDiff));
				gtPartyBUpnlAfterClose = gtPartyBUpnlAfterClose.checkedAdd(gtPartyBDelta);
			}
		}

		return (gtPartyBAvailableBalance, gtPartyAAvailableBalance, gtPartyBUpnlAfterClose);
	}

	function isSolventAfterClosePosition(
		uint256[] memory quoteIds,
		gtUint256[] memory gtFilledAmounts,
		gtUint256[] memory gtClosedPrices,
		uint256[] memory marketPrices,
		gtInt256 gtUpnlPartyB,
		gtInt256 gtUpnlPartyA,
		address partyB,
		address partyA
	) internal returns (bool) {
		(gtInt256 gtPartyBAvailableBalance, gtInt256 gtPartyAAvailableBalance) = getAvailableBalanceAfterClosePosition(
			quoteIds,
			gtFilledAmounts,
			gtClosedPrices,
			marketPrices,
			gtUpnlPartyB,
			gtUpnlPartyA,
			partyB,
			partyA
		);

		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtPartyBAvailableBalance.ge(gtZero)), "LibSolvency: Available partyB balance is lower than zero");
		require(MpcCore.decrypt(gtPartyAAvailableBalance.ge(gtZero)), "LibSolvency: Available partyA balance is lower than zero");
		return true;
	}
}
