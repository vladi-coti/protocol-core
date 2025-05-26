// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyBPositionActionsFacetImpl.sol";
import "./IPartyBPositionActionsPrivateFacet.sol";
import "./IPartyBPositionActionsEvents.sol";
import "../../libraries/LibPartyBPositionsActions.sol";
import "../../libraries/LibPrivateQuote.sol";
import "../../libraries/muon/LibMuonPartyB.sol";
import "../../libraries/LibSolvency.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PartyBPositionActionsPrivateFacet is Accessibility, Pausable, IPartyBPositionActionsPrivateFacet {
	/**
	 * @notice Opens a position with optional private variable support
	 * @param quoteId The ID of the quote for which the position is opened
	 * @param filledAmount PartyB has the option to open the position with either the full amount requested by the user or a specific fraction of it
	 * @param openedPrice The opened price for the position
	 * @param upnlSig The Muon signature containing PairUpnlAndPriceSig data
	 * @param usePrivateMode Whether to enable private variables for this position
	 */
	function openPositionWithPrivacy(
		uint256 quoteId,
		uint256 filledAmount,
		uint256 openedPrice,
		PairUpnlAndPriceSig memory upnlSig,
		bool usePrivateMode
	) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		// Enable private mode if requested and not already enabled
		if (usePrivateMode && !LibPrivateQuote.isPrivateQuote(quoteId)) {
			LibPartyBPositionsActions.enablePrivateMode(quoteId, msg.sender);
		}

		// Use the enhanced position opening with privacy support
		uint256 newId = LibPartyBPositionsActions.openPositionWithPrivacy(quoteId, filledAmount, openedPrice, usePrivateMode, msg.sender);

		// Verify solvency after opening position
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);
		accountLayout.partyANonces[quote.partyA] += 1;
		accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;

		uint256[] memory quoteIds = new uint256[](1);
		uint256[] memory filledAmounts = new uint256[](1);
		uint256[] memory marketPrices = new uint256[](1);
		quoteIds[0] = quoteId;
		filledAmounts[0] = filledAmount;
		marketPrices[0] = upnlSig.price;

		LibSolvency.isSolventAfterOpenPosition(
			quoteIds,
			filledAmounts,
			marketPrices,
			upnlSig.upnlPartyB,
			upnlSig.upnlPartyA,
			quote.partyB,
			quote.partyA
		);

		// Emit events
		emit OpenPosition(quoteId, quote.partyA, quote.partyB, filledAmount, openedPrice);

		if (newId != 0) {
			Quote storage newQuote = QuoteStorage.layout().quotes[newId];
			if (newQuote.quoteStatus == QuoteStatus.PENDING) {
				// For private quotes, emit with encrypted or placeholder values
				uint256 emitQuantity = usePrivateMode ? 0 : newQuote.quantity; // Use 0 for privacy

				emit SendQuote(
					newQuote.partyA,
					newQuote.id,
					newQuote.partyBsWhiteList,
					newQuote.symbolId,
					newQuote.positionType,
					newQuote.orderType,
					newQuote.requestedOpenPrice,
					newQuote.marketPrice,
					emitQuantity, // Private quantity hidden
					newQuote.lockedValues.cva,
					newQuote.lockedValues.lf,
					newQuote.lockedValues.partyAmm,
					newQuote.lockedValues.partyBmm,
					newQuote.tradingFee,
					newQuote.deadline
				);
			} else if (newQuote.quoteStatus == QuoteStatus.CANCELED) {
				emit AcceptCancelRequest(newQuote.id, QuoteStatus.CANCELED);
			}
		}
	}
}
