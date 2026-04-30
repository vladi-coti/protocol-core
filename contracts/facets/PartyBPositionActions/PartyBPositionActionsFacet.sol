// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyBPositionActionsFacetImpl.sol";
import "./IPartyBPositionActionsEvents.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PartyBPositionActionsFacet is Accessibility, Pausable, IPartyBPositionActionsEvents {
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
		
		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		address partyBAddr = LibAccount.getUserEncryptionAddress(quote.partyB);
		ctUint256 memory filledAmountA = MpcCore.offBoardToUser(gtFilledAmount, partyAAddr);
		ctUint256 memory openedPriceA = MpcCore.offBoardToUser(gtOpenedPrice, partyAAddr);
		ctUint256 memory filledAmountB = MpcCore.offBoardToUser(gtFilledAmount, partyBAddr);
		ctUint256 memory openedPriceB = MpcCore.offBoardToUser(gtOpenedPrice, partyBAddr);
		emit OpenPositionForPartyA(quoteId, quote.partyA, quote.partyB, EncryptedPositionValues(filledAmountA, openedPriceA));
		emit OpenPositionForPartyB(quoteId, quote.partyA, quote.partyB, EncryptedPositionValues(filledAmountB, openedPriceB));
		
		if (newId != 0) {
			Quote storage newQuote = QuoteStorage.layout().quotes[newId];
			if (newQuote.quoteStatus == QuoteStatus.PENDING) {
				gtUint256 gtPrice = MpcCore.onBoard(newQuote.requestedOpenPrice.ciphertext);
				gtUint256 gtQuantity = MpcCore.onBoard(newQuote.quantity.ciphertext);
				address newQuotePartyAAddr = LibAccount.getUserEncryptionAddress(newQuote.partyA);
				gtUint256 gtMarketPrice = MpcCore.setPublic256(upnlSig.price);
				gtUint256 gtTradingFee = MpcCore.setPublic256(SymbolStorage.layout().symbols[newQuote.symbolId].tradingFee);
				GarbledLockedValues memory gtLocked = newQuote.lockedValues.onBoard();
				emit SendQuoteForPartyA(newQuote.partyA, newId, newQuote.partyBsWhiteList, newQuote.symbolId, newQuote.positionType, newQuote.orderType, EncryptedQuoteValues(MpcCore.offBoardToUser(gtPrice, newQuotePartyAAddr), MpcCore.offBoardToUser(gtMarketPrice, newQuotePartyAAddr), MpcCore.offBoardToUser(gtQuantity, newQuotePartyAAddr), MpcCore.offBoardToUser(gtLocked.cva, newQuotePartyAAddr), MpcCore.offBoardToUser(gtLocked.lf, newQuotePartyAAddr), MpcCore.offBoardToUser(gtLocked.partyAmm, newQuotePartyAAddr), MpcCore.offBoardToUser(gtLocked.partyBmm, newQuotePartyAAddr), MpcCore.offBoardToUser(gtTradingFee, newQuotePartyAAddr)), newQuote.deadline);
				for (uint256 i = 0; i < newQuote.partyBsWhiteList.length; i++) {
					address newQuotePartyBAddr = LibAccount.getUserEncryptionAddress(newQuote.partyBsWhiteList[i]);
					emit SendQuoteForPartyB(newQuote.partyA, newId, newQuote.partyBsWhiteList[i], newQuote.symbolId, newQuote.positionType, newQuote.orderType, EncryptedQuoteValues(MpcCore.offBoardToUser(gtPrice, newQuotePartyBAddr), MpcCore.offBoardToUser(gtMarketPrice, newQuotePartyBAddr), MpcCore.offBoardToUser(gtQuantity, newQuotePartyBAddr), MpcCore.offBoardToUser(gtLocked.cva, newQuotePartyBAddr), MpcCore.offBoardToUser(gtLocked.lf, newQuotePartyBAddr), MpcCore.offBoardToUser(gtLocked.partyAmm, newQuotePartyBAddr), MpcCore.offBoardToUser(gtLocked.partyBmm, newQuotePartyBAddr), MpcCore.offBoardToUser(gtTradingFee, newQuotePartyBAddr)), newQuote.deadline);
				}
			} else if (newQuote.quoteStatus == QuoteStatus.CANCELED) {
				emit AcceptCancelRequest(newQuote.id, QuoteStatus.CANCELED);
			}
		}
	}

}
