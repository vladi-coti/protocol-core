// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "./PartyBPositionActionsFacetImpl.sol";
import "./IPartyBPositionActionsPrivateFacet.sol";
import "./IPartyBPositionActionsEvents.sol";
import "../../libraries/muon/LibMuonPartyB.sol";
import "../../libraries/LibSolvency.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/GlobalAppStorage.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "../../libraries/LibPartyBPositionsActions.sol";

contract PartyBPositionActionsPrivateFacet is Accessibility, Pausable, IPartyBPositionActionsPrivateFacet {
	/**
	 * @notice Opens a position with private variable support using MPC operations
	 * @param quoteId The ID of the quote for which the position is opened
	 * @param filledAmount The amount to fill (encrypted)
	 * @param openedPrice The opened price for the position
	 * @param upnlSig The Muon signature containing PairUpnlAndPriceSig data
	 */
	function openPositionWithPrivacy(
		uint256 quoteId,
		itUint256 calldata filledAmount,
		uint256 openedPrice,
		PairUpnlAndPriceSig memory upnlSig
	) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		// Get quote for validation
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		// Validate the encrypted filled amount
		gtUint256 gtFilledAmount = MpcCore.validateCiphertext(filledAmount);

		// Decrypt the filled amount for internal processing
		uint256 decryptedFilledAmount = uint256(MpcCore.decrypt(gtFilledAmount));

		// Validate Muon signature with correct parameters
		LibMuonPartyB.verifyPairUpnlAndPrice(upnlSig, quote.partyB, quote.partyA, quote.symbolId);

		// Use the private position opening logic
		uint256 newId = LibPartyBPositionsActions.openPositionWithPrivacy(quoteId, decryptedFilledAmount, openedPrice);

		// Emit private event with encrypted filled amount for partyA
		ctUint256 memory encryptedForPartyA = MpcCore.offBoardToUser(gtFilledAmount, quote.partyA);
		emit OpenPositionPrivate(quoteId, quote.partyA, quote.partyB, encryptedForPartyA, openedPrice);

		if (newId != 0) {
			Quote storage newQuote = QuoteStorage.layout().quotes[newId];
			if (newQuote.quoteStatus == QuoteStatus.PENDING) {
				// For private quotes, emit with privacy-preserving values
				uint256 emitQuantity = 0; // Hide quantity for privacy

				emit SendQuote(
					newQuote.partyA,
					newQuote.id,
					newQuote.partyBsWhiteList,
					newQuote.symbolId,
					newQuote.positionType,
					newQuote.orderType,
					newQuote.requestedOpenPrice,
					newQuote.marketPrice,
					emitQuantity, // Privacy-preserving quantity
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
