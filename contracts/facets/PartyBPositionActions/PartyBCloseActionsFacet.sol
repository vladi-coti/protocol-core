// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyBPositionActionsFacetImpl.sol";
import "./IPartyBPositionActionsEvents.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PartyBCloseActionsFacet is Accessibility, Pausable, IPartyBPositionActionsEvents {
	using MpcCore for gtUint256;

	/**
	 * @notice Fills the close request for the specified quote.
	 * @param quoteId The ID of the quote for which the close request is filled.
	 * @param encryptedCloseParams The encrypted close parameters containing encrypted filledAmount and closedPrice.
	 * @param upnlSig The Muon signature containing PairUpnlAndPriceSig data.
	 */
	function fillCloseRequest(
		uint256 quoteId,
		PrivateClosePositionParams calldata encryptedCloseParams,
		PairUpnlAndPriceSig memory upnlSig
	) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		gtUint256 gtFilledAmount = MpcCore.validateCiphertext(encryptedCloseParams.encryptedFilledAmount);
		gtUint256 gtClosedPrice = MpcCore.validateCiphertext(encryptedCloseParams.encryptedClosedPrice);

		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		PartyBPositionActionsFacetImpl.fillCloseRequest(quoteId, gtFilledAmount, gtClosedPrice, upnlSig);

		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		address partyBAddr = LibAccount.getUserEncryptionAddress(quote.partyB);
		ctUint256 memory filledAmountA = MpcCore.offBoardToUser(gtFilledAmount, partyAAddr);
		ctUint256 memory closedPriceA = MpcCore.offBoardToUser(gtClosedPrice, partyAAddr);
		ctUint256 memory filledAmountB = MpcCore.offBoardToUser(gtFilledAmount, partyBAddr);
		ctUint256 memory closedPriceB = MpcCore.offBoardToUser(gtClosedPrice, partyBAddr);
		emit FillCloseRequestForPartyA(quoteId, quote.partyA, quote.partyB, EncryptedPositionValues(filledAmountA, closedPriceA), quote.quoteStatus, quoteLayout.closeIds[quoteId]);
		emit FillCloseRequestForPartyB(quoteId, quote.partyA, quote.partyB, EncryptedPositionValues(filledAmountB, closedPriceB), quote.quoteStatus, quoteLayout.closeIds[quoteId]);
	}

	/**
	 * @notice Accepts a cancel close request for the specified quote.
	 * @param quoteId The ID of the quote for which the cancel close request is accepted.
	 */
	function acceptCancelCloseRequest(uint256 quoteId) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		PartyBPositionActionsFacetImpl.acceptCancelCloseRequest(quoteId);
		emit AcceptCancelCloseRequest(quoteId, QuoteStatus.OPENED, QuoteStorage.layout().closeIds[quoteId]);
	}
}
