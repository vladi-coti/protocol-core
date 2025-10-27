// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyBPositionActionsFacetImpl.sol";
import "./IPartyBPositionActionsFacet.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PartyBPositionActionsFacet is Accessibility, Pausable, IPartyBPositionActionsFacet {
	using MpcCore for gtUint256;
	using LockedValuesOps for LockedValues;

	/**
	 * @notice Opens a position for the specified quote. The opened position's size can't be excessively small or large.
	 * 			If it's like 99/100, the leftover will be a minuscule quote that falls below the minimum acceptable quote value.
	 * 			Conversely, the position might be so small that it also falls beneath the minimum value.
	 * 			Also, the remaining open portion of the position cannot fall below the minimum acceptable quote value for that particular symbol.
	 * @param quoteId The ID of the quote for which the position is opened.
	 * @param encryptedParams Struct containing encrypted filledAmount and openedPrice parameters
	 * @param upnlSig The Muon signature containing PairUpnlAndPriceSig data.
	 */
	function openPosition(
		uint256 quoteId,
		PrivateOpenPositionParams calldata encryptedParams,
		PairUpnlAndPriceSig memory upnlSig
	) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		// Validate and convert encrypted parameters to garbled values
		gtUint256 gtFilledAmount = MpcCore.validateCiphertext(encryptedParams.encryptedFilledAmount);
		gtUint256 gtOpenedPrice = MpcCore.validateCiphertext(encryptedParams.encryptedOpenedPrice);
		
		uint256 newId = PartyBPositionActionsFacetImpl.openPosition(quoteId, gtFilledAmount, gtOpenedPrice, upnlSig);
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		
		// Emit encrypted position events for both parties
		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			EncryptedPositionValues memory partyAValues = EncryptedPositionValues({
				filledAmount: MpcCore.offBoardToUser(gtFilledAmount, partyAEncryptionAddress),
				openedPrice: MpcCore.offBoardToUser(gtOpenedPrice, partyAEncryptionAddress)
			});
			emit OpenPositionForPartyA(quoteId, quote.partyA, quote.partyB, partyAValues);
		}
		{
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
			EncryptedPositionValues memory partyBValues = EncryptedPositionValues({
				filledAmount: MpcCore.offBoardToUser(gtFilledAmount, partyBEncryptionAddress),
				openedPrice: MpcCore.offBoardToUser(gtOpenedPrice, partyBEncryptionAddress)
			});
			emit OpenPositionForPartyB(quoteId, quote.partyA, quote.partyB, partyBValues);
		}
		
		if (newId != 0) {
			Quote storage newQuote = QuoteStorage.layout().quotes[newId];
			if (newQuote.quoteStatus == QuoteStatus.PENDING) {
				gtUint256 gtPrice = MpcCore.onBoard(newQuote.requestedOpenPrice.ciphertext);
				gtUint256 gtQuantity = MpcCore.onBoard(newQuote.quantity.ciphertext);
				{
					address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(newQuote.partyA);
					EncryptedQuoteValues memory partyAValues = EncryptedQuoteValues({
						price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
						marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
						quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
						cva: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.cva.ciphertext), partyAEncryptionAddress),
						lf: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.lf.ciphertext), partyAEncryptionAddress),
						partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyAmm.ciphertext), partyAEncryptionAddress),
						partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyBmm.ciphertext), partyAEncryptionAddress),
						tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[newQuote.symbolId].tradingFee), partyAEncryptionAddress)
					});
					emit SendQuoteForPartyA(
						msg.sender,
						newId,
						newQuote.partyBsWhiteList,
						newQuote.symbolId,
						newQuote.positionType,
						newQuote.orderType,
						partyAValues,
						newQuote.deadline
					);
				}
				{
					for (uint256 i = 0; i < newQuote.partyBsWhiteList.length; i++) {
						address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(newQuote.partyBsWhiteList[i]);
						EncryptedQuoteValues memory partyBValues = EncryptedQuoteValues({
							price: MpcCore.offBoardToUser(gtPrice, partyBEncryptionAddress),
							marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyBEncryptionAddress),
							quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
							cva: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.cva.ciphertext), partyBEncryptionAddress),
							lf: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.lf.ciphertext), partyBEncryptionAddress),
							partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyAmm.ciphertext), partyBEncryptionAddress),
							partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyBmm.ciphertext), partyBEncryptionAddress),
							tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[newQuote.symbolId].tradingFee), partyBEncryptionAddress)
						});
						emit SendQuoteForPartyB(
							msg.sender,
							newId,
							partyBEncryptionAddress,
							newQuote.symbolId,
							newQuote.positionType,
							newQuote.orderType,
							partyBValues,
							newQuote.deadline
						);
					}
				}
			} else if (newQuote.quoteStatus == QuoteStatus.CANCELED) {
				emit AcceptCancelRequest(newQuote.id, QuoteStatus.CANCELED);
			}
		}
	}

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
		
		// Emit encrypted position events for both parties
		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			EncryptedPositionValues memory partyAValues = EncryptedPositionValues({
				filledAmount: MpcCore.offBoardToUser(gtFilledAmount, partyAEncryptionAddress),
				openedPrice: MpcCore.offBoardToUser(gtClosedPrice, partyAEncryptionAddress)
			});
			emit FillCloseRequestForPartyA(quoteId, quote.partyA, quote.partyB, partyAValues, quote.quoteStatus, quoteLayout.closeIds[quoteId]);
		}
		{
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
			EncryptedPositionValues memory partyBValues = EncryptedPositionValues({
				filledAmount: MpcCore.offBoardToUser(gtFilledAmount, partyBEncryptionAddress),
				openedPrice: MpcCore.offBoardToUser(gtClosedPrice, partyBEncryptionAddress)
			});
			emit FillCloseRequestForPartyB(quoteId, quote.partyA, quote.partyB, partyBValues, quote.quoteStatus, quoteLayout.closeIds[quoteId]);
		}
	}

	/**
	 * @notice Accepts a cancel close request for the specified quote.
	 * @param quoteId The ID of the quote for which the cancel close request is accepted.
	 */
	function acceptCancelCloseRequest(uint256 quoteId) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		PartyBPositionActionsFacetImpl.acceptCancelCloseRequest(quoteId);
		emit AcceptCancelCloseRequest(quoteId, QuoteStatus.OPENED, QuoteStorage.layout().closeIds[quoteId]);
	}

	/**
	 * @notice Allows Party B to emergency close a position for the specified quote.
	 * @param quoteId The ID of the quote for which the position is emergency closed.
	 * @param upnlSig The Muon signature containing the unrealized profit and loss (UPNL) and the closing price.
	 */
	function emergencyClosePosition(
		uint256 quoteId,
		PairUpnlAndPriceSig memory upnlSig
	) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		// FIXME: commented out because it's pushes the contract size over the limit
		
		// QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		// Quote storage quote = quoteLayout.quotes[quoteId];
		
		// // Decrypt quoteOpenAmount for event
		// gtUint256 gtFilledAmount = LibQuote.quoteOpenAmount(quote);
		// uint256 filledAmount = MpcCore.decrypt(gtFilledAmount);
		
		// PartyBPositionActionsFacetImpl.emergencyClosePosition(quoteId, upnlSig);
		// emit EmergencyClosePosition(
		// 	quoteId,
		// 	quote.partyA,
		// 	quote.partyB,
		// 	filledAmount,
		// 	upnlSig.price,
		// 	quote.quoteStatus,
		// 	quoteLayout.closeIds[quoteId]
		// );
		// emit EmergencyClosePosition(quoteId, quote.partyA, quote.partyB, filledAmount, upnlSig.price, quote.quoteStatus); // For backward compatibility, will be removed in future
	}
}
