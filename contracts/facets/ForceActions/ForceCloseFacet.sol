// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "../../interfaces/IPartiesEvents.sol";
import "./ForceActionsFacetEvents.sol";
import "./ForceActionsFacetImpl.sol";
import "../../libraries/LibEncryption.sol";

contract ForceCloseFacet is Accessibility, Pausable, IPartiesEvents, ForceActionsFacetEvents {
	using MpcCore for gtUint256;
	using LockedValuesOps for LockedValues;

	/**
	 * @notice Forces the closure of the position associated with the specified quote.
	 * @param quoteId The ID of the quote for which the position should be forced to close.
	 * @param sig The Muon high-low price signature.
	 */
	function forceClosePosition(
		uint256 quoteId,
		HighLowPriceSig memory sig,
		QuotePriceSig memory partyAPriceSig,
		QuotePriceSig memory partyBPriceSig
	) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];

		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);

		SettlementSig memory settleSig;
		(gtUint256 gtClosePrice, bool isPartyBLiquidated, gtInt256 gtUpnlPartyB, gtUint256 gtPartyBAllocatedBalance) = ForceActionsFacetImpl.forceClosePosition(
			quoteId,
			sig,
			settleSig,
			new uint256[](0),
			partyAPriceSig,
			partyBPriceSig
		);
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);

		if (isPartyBLiquidated) {
			ctUint256 memory ctPartyBAllocatedBalance = MpcCore.offBoardToUser(gtPartyBAllocatedBalance, partyBEncryptionAddress);
			ctInt256 memory ctUpnlPartyB = MpcCore.offBoardToUser(gtUpnlPartyB, partyBEncryptionAddress);
			emit LiquidatePartyB(msg.sender, quote.partyB, quote.partyA, ctPartyBAllocatedBalance, ctUpnlPartyB);
			emit ObserverForceLiquidatePartyB(
				msg.sender,
				quote.partyB,
				quote.partyA,
				LibEncryption.offBoardToObserver(gtPartyBAllocatedBalance),
				LibEncryption.offBoardToObserver(gtUpnlPartyB)
			);
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
			emit ObserverForceClosePosition(
				quoteId,
				quote.partyA,
				quote.partyB,
				LibEncryption.offBoardToObserver(gtQuantityToClose),
				LibEncryption.offBoardToObserver(gtClosePrice),
				quote.quoteStatus,
				quoteLayout.closeIds[quoteId]
			);
		}
	}

	function forceClosePositionWithQuotePrices(
		uint256 quoteId,
		HighLowPriceSig memory sig,
		QuotePriceSig memory partyAPriceSig,
		QuotePriceSig memory partyBPriceSig
	) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];

		gtUint256 gtQuantityToClose = LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext);

		SettlementSig memory settleSig;
		(gtUint256 gtClosePrice, bool isPartyBLiquidated, gtInt256 gtUpnlPartyB, gtUint256 gtPartyBAllocatedBalance) = ForceActionsFacetImpl.forceClosePosition(
			quoteId,
			sig,
			settleSig,
			new uint256[](0),
			partyAPriceSig,
			partyBPriceSig
		);
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);

		if (isPartyBLiquidated) {
			ctUint256 memory ctPartyBAllocatedBalance = MpcCore.offBoardToUser(gtPartyBAllocatedBalance, partyBEncryptionAddress);
			ctInt256 memory ctUpnlPartyB = MpcCore.offBoardToUser(gtUpnlPartyB, partyBEncryptionAddress);
			emit LiquidatePartyB(msg.sender, quote.partyB, quote.partyA, ctPartyBAllocatedBalance, ctUpnlPartyB);
			emit ObserverForceLiquidatePartyB(
				msg.sender,
				quote.partyB,
				quote.partyA,
				LibEncryption.offBoardToObserver(gtPartyBAllocatedBalance),
				LibEncryption.offBoardToObserver(gtUpnlPartyB)
			);
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
			emit ObserverForceClosePosition(
				quoteId,
				quote.partyA,
				quote.partyB,
				LibEncryption.offBoardToObserver(gtQuantityToClose),
				LibEncryption.offBoardToObserver(gtClosePrice),
				quote.quoteStatus,
				quoteLayout.closeIds[quoteId]
			);
		}
	}

}
