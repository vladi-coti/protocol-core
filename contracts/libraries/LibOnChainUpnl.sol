// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../storages/MuonStorage.sol";
import "../storages/QuoteStorage.sol";
import "./LibEncryption.sol";
import "./LibQuote.sol";

library LibOnChainUpnl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;

	function priceSigFromSingle(SingleUpnlSig memory sig) internal pure returns (QuotePriceSig memory priceSig) {
		priceSig = QuotePriceSig({
			reqId: sig.reqId,
			timestamp: sig.timestamp,
			quoteIds: sig.quoteIds,
			prices: sig.prices,
			gatewaySignature: sig.gatewaySignature,
			sigs: sig.sigs
		});
	}

	function priceSigFromSingleAndPrice(SingleUpnlAndPriceSig memory sig) internal pure returns (QuotePriceSig memory priceSig) {
		priceSig = QuotePriceSig({
			reqId: sig.reqId,
			timestamp: sig.timestamp,
			quoteIds: sig.quoteIds,
			prices: sig.prices,
			gatewaySignature: sig.gatewaySignature,
			sigs: sig.sigs
		});
	}

	function partyAPriceSigFromPair(PairUpnlSig memory sig) internal pure returns (QuotePriceSig memory priceSig) {
		priceSig = QuotePriceSig({
			reqId: sig.reqId,
			timestamp: sig.timestamp,
			quoteIds: sig.partyAQuoteIds,
			prices: sig.partyAPrices,
			gatewaySignature: sig.gatewaySignature,
			sigs: sig.sigs
		});
	}

	function partyBPriceSigFromPair(PairUpnlSig memory sig) internal pure returns (QuotePriceSig memory priceSig) {
		priceSig = QuotePriceSig({
			reqId: sig.reqId,
			timestamp: sig.timestamp,
			quoteIds: sig.partyBQuoteIds,
			prices: sig.partyBPrices,
			gatewaySignature: sig.gatewaySignature,
			sigs: sig.sigs
		});
	}

	function partyAPriceSigFromPairAndPrice(PairUpnlAndPriceSig memory sig) internal pure returns (QuotePriceSig memory priceSig) {
		priceSig = QuotePriceSig({
			reqId: sig.reqId,
			timestamp: sig.timestamp,
			quoteIds: sig.partyAQuoteIds,
			prices: sig.partyAPrices,
			gatewaySignature: sig.gatewaySignature,
			sigs: sig.sigs
		});
	}

	function partyBPriceSigFromPairAndPrice(PairUpnlAndPriceSig memory sig) internal pure returns (QuotePriceSig memory priceSig) {
		priceSig = QuotePriceSig({
			reqId: sig.reqId,
			timestamp: sig.timestamp,
			quoteIds: sig.partyBQuoteIds,
			prices: sig.partyBPrices,
			gatewaySignature: sig.gatewaySignature,
			sigs: sig.sigs
		});
	}

	function partyAUpnlFromQuotePrices(address partyA, QuotePriceSig memory priceSig) internal returns (gtInt256 gtUpnl) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		uint256[] storage openPositions = quoteLayout.partyAOpenPositions[partyA];
		require(priceSig.quoteIds.length == openPositions.length, "LibOnChainUpnl: Invalid price count");

		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		gtUpnl = gtZero;

		for (uint256 i = 0; i < openPositions.length; i++) {
			uint256 quoteId = openPositions[i];
			require(priceSig.quoteIds[i] == quoteId, "LibOnChainUpnl: Invalid quote order");
			Quote storage quote = quoteLayout.quotes[quoteId];

			gtUint256 gtPrice = MpcCore.setPublic256(priceSig.prices[i]);
			gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
			(gtBool gtHasMadeProfit, gtUint256 gtPnl) = LibQuote.getValueOfQuoteForPartyA(gtPrice, gtOpenAmount, quote);

			gtInt256 gtSignedPnl = LibEncryption.toNonNegativeSigned(gtPnl);
			// COTI mux(bit,a,b)=bit?b:a — profit => +pnl, loss => -pnl
			gtInt256 gtDelta = MpcCore.mux(gtHasMadeProfit, gtZero.checkedSub(gtSignedPnl), gtSignedPnl);
			gtUpnl = gtUpnl.checkedAdd(gtDelta);
		}
	}

	function partyBUpnlFromQuotePrices(address partyB, address partyA, QuotePriceSig memory priceSig) internal returns (gtInt256 gtUpnl) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		uint256[] storage openPositions = quoteLayout.partyBOpenPositions[partyB][partyA];
		require(priceSig.quoteIds.length == openPositions.length, "LibOnChainUpnl: Invalid price count");

		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		gtUpnl = gtZero;

		for (uint256 i = 0; i < openPositions.length; i++) {
			uint256 quoteId = openPositions[i];
			require(priceSig.quoteIds[i] == quoteId, "LibOnChainUpnl: Invalid quote order");
			Quote storage quote = quoteLayout.quotes[quoteId];

			gtUint256 gtPrice = MpcCore.setPublic256(priceSig.prices[i]);
			gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
			(gtBool gtPartyAHasMadeProfit, gtUint256 gtPnl) = LibQuote.getValueOfQuoteForPartyA(gtPrice, gtOpenAmount, quote);

			gtInt256 gtSignedPnl = LibEncryption.toNonNegativeSigned(gtPnl);
			// PartyB is opposite PartyA: COTI mux(bit,a,b)=bit?b:a — A-profit => B -pnl
			gtInt256 gtDelta = MpcCore.mux(gtPartyAHasMadeProfit, gtSignedPnl, gtZero.checkedSub(gtSignedPnl));
			gtUpnl = gtUpnl.checkedAdd(gtDelta);
		}
	}

	function partyAUpnlAndLossFromSymbolPrices(
		address partyA,
		uint256[] memory symbolIds,
		uint256[] memory prices
	) internal returns (gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) {
		require(symbolIds.length == prices.length, "LibOnChainUpnl: Invalid symbol price count");
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		uint256[] storage openPositions = quoteLayout.partyAOpenPositions[partyA];

		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		gtUpnl = gtZero;
		gtTotalUnrealizedLoss = gtZero;

		for (uint256 i = 0; i < openPositions.length; i++) {
			Quote storage quote = quoteLayout.quotes[openPositions[i]];
			gtUint256 gtPrice = MpcCore.setPublic256(_priceForSymbol(quote.symbolId, symbolIds, prices));
			gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
			(gtBool gtHasMadeProfit, gtUint256 gtPnl) = LibQuote.getValueOfQuoteForPartyA(gtPrice, gtOpenAmount, quote);

			gtInt256 gtSignedPnl = LibEncryption.toNonNegativeSigned(gtPnl);
			gtInt256 gtNegativePnl = gtZero.checkedSub(gtSignedPnl);
			// COTI mux(bit,a,b)=bit?b:a — profit => +pnl / keep loss; loss => -pnl / accumulate signed loss
			gtInt256 gtDelta = MpcCore.mux(gtHasMadeProfit, gtNegativePnl, gtSignedPnl);
			gtUpnl = gtUpnl.checkedAdd(gtDelta);
			gtTotalUnrealizedLoss = MpcCore.mux(
				gtHasMadeProfit,
				gtTotalUnrealizedLoss.checkedAdd(gtNegativePnl),
				gtTotalUnrealizedLoss
			);
		}
	}

	function _priceForSymbol(uint256 symbolId, uint256[] memory symbolIds, uint256[] memory prices) private pure returns (uint256) {
		for (uint256 i = 0; i < symbolIds.length; i++) {
			if (symbolIds[i] == symbolId) {
				return prices[i];
			}
		}
		revert("LibOnChainUpnl: Missing symbol price");
	}
}
