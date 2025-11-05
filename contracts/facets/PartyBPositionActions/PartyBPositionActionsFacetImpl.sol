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

		require(!accountLayout.suspendedAddresses[quote.partyA], "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[msg.sender], "PartyBFacet: Sender is Suspended");
		require(!appLayout.partyBEmergencyStatus[quote.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");
		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);
		accountLayout.partyANonces[quote.partyA]++;
		accountLayout.partyBNonces[quote.partyB][quote.partyA]++;

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

	function fillCloseRequest(uint256 quoteId, gtUint256 gtFilledAmount, gtUint256 gtClosedPrice, PairUpnlAndPriceSig memory upnlSig) internal {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);
		uint256[] memory quoteIds = new uint256[](1);
		quoteIds[0] = quoteId;
		gtUint256[] memory gtFilledAmounts = new gtUint256[](1);
		gtFilledAmounts[0] = gtFilledAmount;
		gtUint256[] memory gtClosedPrices = new gtUint256[](1);
		gtClosedPrices[0] = gtClosedPrice;
		uint256[] memory marketPrices = new uint256[](1);
		marketPrices[0] = upnlSig.price;
		LibSolvency.isSolventAfterClosePosition(quoteIds, gtFilledAmounts, gtClosedPrices, marketPrices, upnlSig.upnlPartyB, upnlSig.upnlPartyA, quote.partyB, quote.partyA);
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		accountLayout.partyBNonces[quote.partyB][quote.partyA]++;
		accountLayout.partyANonces[quote.partyA]++;
		LibPartyBPositionsActions.fillCloseRequest(quoteId, gtFilledAmount, gtClosedPrice);
	}

	function acceptCancelCloseRequest(uint256 quoteId) internal {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING, "PartyBFacet: Invalid state");
		quote.statusModifyTimestamp = block.timestamp;
		quote.quoteStatus = QuoteStatus.OPENED;
		gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		quote.requestedClosePrice = gtZero.offBoardCombined(partyAAddr);
		quote.quantityToClose = gtZero.offBoardCombined(partyAAddr);
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
		
		// Get encrypted quoteOpenAmount
		gtUint256 gtFilledAmount = LibQuote.quoteOpenAmount(quote);
		
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
		
		accountLayout.partyBNonces[quote.partyB][quote.partyA]++;
		accountLayout.partyANonces[quote.partyA]++;
		LibQuote.closeQuote(quote, gtFilledAmount, gtPrice);
	}
}
