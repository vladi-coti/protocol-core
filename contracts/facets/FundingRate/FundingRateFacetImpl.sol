// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/muon/LibMuonFundingRate.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibEncryption.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library FundingRateFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function chargeFundingRate(address partyA, uint256[] memory quoteIds, int256[] memory rates, PairUpnlSig memory upnlSig) internal {
		LibMuonFundingRate.verifyPairUpnl(upnlSig, msg.sender, partyA);
		require(quoteIds.length == rates.length && quoteIds.length > 0, "ChargeFundingFacet: Length not match");
		
		// Get encrypted available balances
		gtInt256 gtPartyBAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlSig.upnlPartyB, msg.sender, partyA);
		gtInt256 gtPartyAAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(upnlSig.upnlPartyA, partyA);
		uint256 epochDuration;
		uint256 windowTime;
		for (uint256 i = 0; i < quoteIds.length; i++) {
			Quote storage quote = QuoteStorage.layout().quotes[quoteIds[i]];
			require(quote.partyA == partyA, "ChargeFundingFacet: Invalid quote");
			require(quote.partyB == msg.sender, "ChargeFundingFacet: Sender isn't partyB of quote");
			require(
				quote.quoteStatus == QuoteStatus.OPENED ||
					quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
					quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
				"ChargeFundingFacet: Invalid state"
			);
			epochDuration = SymbolStorage.layout().symbols[quote.symbolId].fundingRateEpochDuration;
			require(epochDuration > 0, "ChargeFundingFacet: Zero funding epoch duration");
			windowTime = SymbolStorage.layout().symbols[quote.symbolId].fundingRateWindowTime;
			uint256 latestEpochTimestamp = (block.timestamp / epochDuration) * epochDuration;
			uint256 paidTimestamp;
			if (block.timestamp <= latestEpochTimestamp + windowTime) {
				require(latestEpochTimestamp > quote.lastFundingPaymentTimestamp, "ChargeFundingFacet: Funding already paid for this window");
				paidTimestamp = latestEpochTimestamp;
			} else {
				uint256 nextEpochTimestamp = latestEpochTimestamp + epochDuration;
				require(block.timestamp >= nextEpochTimestamp - windowTime, "ChargeFundingFacet: Current timestamp is out of window");
				require(nextEpochTimestamp > quote.lastFundingPaymentTimestamp, "ChargeFundingFacet: Funding already paid for this window");
				paidTimestamp = nextEpochTimestamp;
			}
			// Get encrypted openedPrice and quoteOpenAmount
			gtUint256 gtOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			gtUint256 gtScaleFactor = MpcCore.setPublic256(uint256(1e18));
			
			if (rates[i] >= 0) {
				require(uint256(rates[i]) <= quote.maxFundingRate, "ChargeFundingFacet: High funding rate");
				
				// Calculate priceDiff encrypted
				gtUint256 gtRate = MpcCore.setPublic256(uint256(rates[i]));
				gtUint256 gtPriceDiff = gtOpenedPrice.checkedMul(gtRate).div(gtScaleFactor);
				
				// Update openedPrice
				if (quote.positionType == PositionType.LONG) {
					gtOpenedPrice = gtOpenedPrice.checkedAdd(gtPriceDiff);
				} else {
					gtOpenedPrice = gtOpenedPrice.checkedSub(gtPriceDiff);
				}
				quote.openedPrice = gtOpenedPrice.offBoardCombined(LibAccount.getUserEncryptionAddress(quote.partyA));
				QuoteStorage.layout().observerQuoteValues[quote.id].openedPrice = LibEncryption.offBoardToObserver(gtOpenedPrice);
				
				// Calculate impact on balances
				gtInt256 gtImpact = gtQuoteOpenAmount.checkedMul(gtPriceDiff).div(gtScaleFactor).toSigned();
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.sub(gtImpact);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.add(gtImpact);
			} else {
				require(uint256(-rates[i]) <= quote.maxFundingRate, "ChargeFundingFacet: High funding rate");
				
				// Calculate priceDiff encrypted
				gtUint256 gtRate = MpcCore.setPublic256(uint256(-rates[i]));
				gtUint256 gtPriceDiff = gtOpenedPrice.checkedMul(gtRate).div(gtScaleFactor);
				
				// Update openedPrice
				if (quote.positionType == PositionType.LONG) {
					gtOpenedPrice = gtOpenedPrice.checkedSub(gtPriceDiff);
				} else {
					gtOpenedPrice = gtOpenedPrice.checkedAdd(gtPriceDiff);
				}
				quote.openedPrice = gtOpenedPrice.offBoardCombined(LibAccount.getUserEncryptionAddress(quote.partyA));
				QuoteStorage.layout().observerQuoteValues[quote.id].openedPrice = LibEncryption.offBoardToObserver(gtOpenedPrice);
				
				// Calculate impact on balances
				gtInt256 gtImpact = gtQuoteOpenAmount.checkedMul(gtPriceDiff).div(gtScaleFactor).toSigned();
				gtPartyAAvailableBalance = gtPartyAAvailableBalance.add(gtImpact);
				gtPartyBAvailableBalance = gtPartyBAvailableBalance.sub(gtImpact);
			}
			quote.lastFundingPaymentTimestamp = paidTimestamp;
		}
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		gtBool isPartyAInsolvent = MpcCore.lt(gtPartyAAvailableBalance, gtZero);
		require(!MpcCore.decrypt(isPartyAInsolvent), "ChargeFundingFacet: PartyA will be insolvent");
		gtBool isPartyBInsolvent = MpcCore.lt(gtPartyBAvailableBalance, gtZero);
		require(!MpcCore.decrypt(isPartyBInsolvent), "ChargeFundingFacet: PartyB will be insolvent");
		AccountStorage.layout().partyBNonces[msg.sender][partyA] += 1;
		AccountStorage.layout().partyANonces[partyA] += 1;
	}
}
