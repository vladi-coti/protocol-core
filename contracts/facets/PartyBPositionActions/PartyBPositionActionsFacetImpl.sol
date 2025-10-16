// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/muon/LibMuonPartyB.sol";
import "../../libraries/LibSolvency.sol";
import "../../libraries/LibPartyBPositionsActions.sol";

library PartyBPositionActionsFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function openPosition(
		uint256 quoteId,
		gtUint256 gtFilledAmount,
		gtUint256 gtOpenedPrice,
		PairUpnlAndPriceSig memory upnlSig
	) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();

		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		require(accountLayout.suspendedAddresses[quote.partyA] == false, "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[msg.sender], "PartyBFacet: Sender is Suspended");
		require(!appLayout.partyBEmergencyStatus[quote.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");
		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);
		accountLayout.partyANonces[quote.partyA] += 1;
		accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;

		currentId = LibPartyBPositionsActions.openPosition(quoteId, gtFilledAmount, gtOpenedPrice);
		LibSolvency.isSolventAfterOpenPosition(
			quoteId,
			gtFilledAmount,
			gtOpenedPrice,
			upnlSig.price,
			upnlSig.upnlPartyB,
			upnlSig.upnlPartyA,
			quote.partyB,
			quote.partyA
		);
	}

	function fillCloseRequest(uint256 quoteId, uint256 filledAmount, uint256 closedPrice, PairUpnlAndPriceSig memory upnlSig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);
		uint256[] memory quoteIds = new uint256[](1);
		uint256[] memory filledAmounts = new uint256[](1);
		uint256[] memory closedPrices = new uint256[](1);
		uint256[] memory marketPrices = new uint256[](1);
		quoteIds[0] = quoteId;
		filledAmounts[0] = filledAmount;
		closedPrices[0] = closedPrice;
		marketPrices[0] = upnlSig.price;
		LibSolvency.isSolventAfterClosePosition(
			quoteIds,
			filledAmounts,
			closedPrices,
			marketPrices,
			upnlSig.upnlPartyB,
			upnlSig.upnlPartyA,
			quote.partyB,
			quote.partyA
		);
		accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;
		accountLayout.partyANonces[quote.partyA] += 1;
		LibPartyBPositionsActions.fillCloseRequest(quoteId, filledAmount, closedPrice);
	}

	function acceptCancelCloseRequest(uint256 quoteId) internal {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING, "PartyBFacet: Invalid state");
		quote.statusModifyTimestamp = block.timestamp;
		quote.quoteStatus = QuoteStatus.OPENED;
		
		// Set encrypted fields to zero
		gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
		quote.requestedClosePrice = gtZero.offBoardCombined(quote.partyA);
		quote.quantityToClose = gtZero.offBoardCombined(quote.partyA);
	}

	function emergencyClosePosition(uint256 quoteId, PairUpnlAndPriceSig memory upnlSig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		Symbol memory symbol = SymbolStorage.layout().symbols[quote.symbolId];
		require(
			GlobalAppStorage.layout().emergencyMode || GlobalAppStorage.layout().partyBEmergencyStatus[quote.partyB] || !symbol.isValid,
			"PartyBFacet: Operation not allowed. Either emergency mode must be active, party B must be in emergency status, or the symbol must be delisted"
		);
		require(quote.quoteStatus == QuoteStatus.OPENED || quote.quoteStatus == QuoteStatus.CLOSE_PENDING, "PartyBFacet: Invalid state");
		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);
		
		// Get encrypted quoteOpenAmount and decrypt
		gtUint256 gtFilledAmount = LibQuote.quoteOpenAmount(quote);
		uint256 filledAmount = MpcCore.decrypt(gtFilledAmount);
		
		// Set encrypted fields
		gtUint256 gtPrice = MpcCore.setPublic256(upnlSig.price);
		quote.quantityToClose = gtFilledAmount.offBoardCombined(quote.partyA);
		quote.requestedClosePrice = gtPrice.offBoardCombined(quote.partyA);
		
		// Check solvency with encrypted balance calculations
		gtInt256 gtPartyAAvailable = LibAccount.partyAAvailableBalanceForLiquidation(upnlSig.upnlPartyA, quote.partyA);
		gtInt256 gtPartyBAvailable = LibAccount.partyBAvailableBalanceForLiquidation(upnlSig.upnlPartyB, quote.partyB, quote.partyA);
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		
		require(MpcCore.decrypt(gtPartyAAvailable.ge(gtZero)), "PartyBFacet: PartyA is insolvent");
		require(MpcCore.decrypt(gtPartyBAvailable.ge(gtZero)), "PartyBFacet: PartyB should be solvent");
		
		accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;
		accountLayout.partyANonces[quote.partyA] += 1;
		LibQuote.closeQuote(quote, filledAmount, upnlSig.price);
	}
}
