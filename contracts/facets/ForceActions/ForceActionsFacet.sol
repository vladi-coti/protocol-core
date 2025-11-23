// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "../../interfaces/IPartiesEvents.sol";
import "./IForceActionsFacet.sol";
import "./ForceActionsFacetImpl.sol";
import "../Settlement/SettlementFacetEvents.sol";

contract ForceActionsFacet is Accessibility, Pausable, IPartiesEvents, IForceActionsFacet, SettlementFacetEvents {
	using MpcCore for gtUint256;
	using LockedValuesOps for LockedValues;
	/**
	 * @notice Forces the cancellation of the specified quote when partyB is not responsive for a certian amount of time(ForceCancelCooldown).
	 * @param quoteId The ID of the quote to be canceled.
	 */
	function forceCancelQuote(uint256 quoteId) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		// FIXME: commented out because it's pushes the contract size over the limit

		// ForceActionsFacetImpl.forceCancelQuote(quoteId);
		// emit ForceCancelQuote(quoteId, QuoteStatus.CANCELED);
	}

	/**
	 * @notice Forces the cancellation of the close request associated with the specified quote when partyB is not responsive for a certain amount of time(ForceCancelCloseCooldown).
	 * @param quoteId The ID of the quote for which the close request should be canceled.
	 */
	function forceCancelCloseRequest(uint256 quoteId) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		ForceActionsFacetImpl.forceCancelCloseRequest(quoteId);
		emit ForceCancelCloseRequest(quoteId, QuoteStatus.OPENED, QuoteStorage.layout().closeIds[quoteId]);
	}

	/**
	 * @notice Forces the closure of the position associated with the specified quote.
	 * @param quoteId The ID of the quote for which the position should be forced to close.
	 * @param sig The Muon signature.
	 */
	function forceClosePosition(uint256 quoteId, HighLowPriceSig memory sig) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		
		// Get encrypted quantityToClose
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);
		
		SettlementSig memory settleSig;
		(gtUint256 gtClosePrice, bool isPartyBLiquidated, gtInt256 gtUpnlPartyB, gtUint256 gtPartyBAllocatedBalance) = ForceActionsFacetImpl.forceClosePosition(
			quoteId,
			sig,
			settleSig,
			new uint256[](0)
		);
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);

		if (isPartyBLiquidated) {
			ctUint256 memory ctPartyBAllocatedBalance = MpcCore.offBoardToUser(gtPartyBAllocatedBalance, partyBEncryptionAddress);
			ctInt256 memory ctUpnlPartyB = MpcCore.offBoardToUser(gtUpnlPartyB, partyBEncryptionAddress);
			emit LiquidatePartyB(msg.sender, quote.partyB, quote.partyA, ctPartyBAllocatedBalance, ctUpnlPartyB);
		} else {
			{
				address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
				ctUint256 memory ctFilledAmount = MpcCore.offBoardToUser(gtQuantityToClose, partyAEncryptionAddress);
				ctUint256 memory ctClosePrice = MpcCore.offBoardToUser(gtClosePrice, partyAEncryptionAddress);
				emit ForceClosePositionForPartyA(quoteId, quote.partyA, quote.partyB, ctFilledAmount, ctClosePrice, quote.quoteStatus, quoteLayout.closeIds[quoteId]);
			}
			{
				ctUint256 memory ctFilledAmount = MpcCore.offBoardToUser(gtQuantityToClose, partyBEncryptionAddress);
				ctUint256 memory ctClosePrice = MpcCore.offBoardToUser(gtClosePrice, partyBEncryptionAddress);
				emit ForceClosePositionForPartyB(quoteId, quote.partyA, quote.partyB, ctFilledAmount, ctClosePrice, quote.quoteStatus, quoteLayout.closeIds[quoteId]);
			}
		}
	}

	/**
	 * @notice Settles the positions then forces the closure of the position associated with the specified quote.
	 * @param quoteId The ID of the quote for which the position should be forced to close.
	 * @param highLowPriceSig The Muon signature.
	 * @param settleSig The data struct contains quoteIds and upnl of parties and market prices
	 * @param updatedPrices New prices to be set as openedPrice for the specified quotes.
	 */
	function settleAndForceClosePosition(
		uint256 quoteId,
		HighLowPriceSig memory highLowPriceSig,
		SettlementSig memory settleSig,
		uint256[] memory updatedPrices
	) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		
		// Get encrypted quantityToClose
		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);
		
		(gtUint256 gtClosePrice, bool isPartyBLiquidated, gtInt256 gtUpnlPartyB, gtUint256 gtPartyBAllocatedBalance) = ForceActionsFacetImpl.forceClosePosition(
			quoteId,
			highLowPriceSig,
			settleSig,
			updatedPrices
		);
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);

		if (isPartyBLiquidated) {
			ctUint256 memory ctPartyBAllocatedBalance = MpcCore.offBoardToUser(gtPartyBAllocatedBalance, partyBEncryptionAddress);
			ctInt256 memory ctUpnlPartyB = MpcCore.offBoardToUser(gtUpnlPartyB, partyBEncryptionAddress);
			emit LiquidatePartyB(msg.sender, quote.partyB, quote.partyA, ctPartyBAllocatedBalance, ctUpnlPartyB);
		} else {
			// Decrypt for event emission
			uint256 partyBAllocatedBalance = MpcCore.decrypt(gtPartyBAllocatedBalance);
			uint256[] memory newPartyBsAllocatedBalances = new uint256[](1);
			newPartyBsAllocatedBalances[0] = partyBAllocatedBalance;
			// Prepare encrypted allocated balance for the event
			ctUint256 memory ctAllocatedBalance = AccountStorage.layout().allocatedBalances[msg.sender].userCiphertext;
			
			emit SettleUpnl(
				settleSig.quotesSettlementsData,
				updatedPrices,
				msg.sender,
				ctAllocatedBalance,
				newPartyBsAllocatedBalances
			);
			
			// Emit encrypted events for both parties
			
			{
				address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
				ctUint256 memory ctFilledAmount = MpcCore.offBoardToUser(gtQuantityToClose, partyAEncryptionAddress);
				ctUint256 memory ctClosePrice = MpcCore.offBoardToUser(gtClosePrice, partyAEncryptionAddress);
				emit ForceClosePositionForPartyA(quoteId, quote.partyA, quote.partyB, ctFilledAmount, ctClosePrice, quote.quoteStatus, quoteLayout.closeIds[quoteId]);
			}
			{
				ctUint256 memory ctFilledAmount = MpcCore.offBoardToUser(gtQuantityToClose, partyBEncryptionAddress);
				ctUint256 memory ctClosePrice = MpcCore.offBoardToUser(gtClosePrice, partyBEncryptionAddress);
				emit ForceClosePositionForPartyB(quoteId, quote.partyA, quote.partyB, ctFilledAmount, ctClosePrice, quote.quoteStatus, quoteLayout.closeIds[quoteId]);
			}
		}
	}
}
