// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyAFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IPartyAFacet.sol";
import "../../storages/SymbolStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../libraries/LibEncryption.sol";

contract PartyAFacet is Accessibility, Pausable, IPartyAFacet {
	/**
	 * @notice Send a Private Quote to the protocol with encrypted parameters. The quote status will be pending.
	 * @param basicParams Struct containing basic quote parameters
	 * @param encryptedParams Struct containing all encrypted parameters
	 * @param upnlSig The Muon signature for user upnl and symbol price
	 */
	function sendQuote(
		QuoteBasicParams calldata basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external whenNotPartyAActionsPaused notLiquidatedPartyA(msg.sender) notSuspended(msg.sender) returns (uint256 quoteId) {
		gtUint256 gtPrice = MpcCore.validateCiphertext(encryptedParams.encryptedPrice);
		gtUint256 gtQuantity = MpcCore.validateCiphertext(encryptedParams.encryptedQuantity);
		gtUint256 gtCva = MpcCore.validateCiphertext(encryptedParams.encryptedCva);
		gtUint256 gtLf = MpcCore.validateCiphertext(encryptedParams.encryptedLf);
		gtUint256 gtPartyAmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyAmm);
		gtUint256 gtPartyBmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyBmm);

		quoteId = PartyAFacetImpl.sendQuote(
			basicParams.partyBsWhiteList,
			basicParams.symbolId,
			basicParams.positionType,
			basicParams.orderType,
			gtPrice,
			gtQuantity,
			gtCva,
			gtLf,
			gtPartyAmm,
			gtPartyBmm,
			basicParams.maxFundingRate,
			basicParams.deadline,
			basicParams.affiliate,
			upnlSig
		);
		
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		ObserverQuoteValues storage observerValues = QuoteStorage.layout().observerQuoteValues[quoteId];
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
		EncryptedQuoteValues memory partyAValues = EncryptedQuoteValues({
			price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
			marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
			quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
			cva: quote.lockedValues.cva.userCiphertext,
			lf: quote.lockedValues.lf.userCiphertext,
			partyAmm: quote.lockedValues.partyAmm.userCiphertext,
			partyBmm: quote.lockedValues.partyBmm.userCiphertext,
			tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyAEncryptionAddress)
		});
		emit SendQuoteForPartyA(
			msg.sender,
			quoteId,
			basicParams.partyBsWhiteList,
			basicParams.symbolId,
			basicParams.positionType,
			basicParams.orderType,
			partyAValues,
			basicParams.deadline
		);
		emit ObserverSendQuote(
			msg.sender,
			quoteId,
			address(0),
			basicParams.symbolId,
			basicParams.positionType,
			basicParams.orderType,
			EncryptedQuoteValues({
				price: observerValues.requestedOpenPrice,
				marketPrice: observerValues.marketPrice,
				quantity: observerValues.quantity,
				cva: observerValues.lockedValues.cva,
				lf: observerValues.lockedValues.lf,
				partyAmm: observerValues.lockedValues.partyAmm,
				partyBmm: observerValues.lockedValues.partyBmm,
				tradingFee: observerValues.tradingFee
			}),
			basicParams.deadline
		);
		for (uint256 i = 0; i < basicParams.partyBsWhiteList.length; i++) {
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(basicParams.partyBsWhiteList[i]);
			EncryptedQuoteValues memory partyBValues = EncryptedQuoteValues({
				price: MpcCore.offBoardToUser(gtPrice, partyBEncryptionAddress),
				marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyBEncryptionAddress),
				quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
				cva: MpcCore.offBoardToUser(gtCva, partyBEncryptionAddress),
				lf: MpcCore.offBoardToUser(gtLf, partyBEncryptionAddress),
				partyAmm: MpcCore.offBoardToUser(gtPartyAmm, partyBEncryptionAddress),
				partyBmm: MpcCore.offBoardToUser(gtPartyBmm, partyBEncryptionAddress),
				tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyBEncryptionAddress)
			});
			emit SendQuoteForPartyB(
				msg.sender,
				quoteId,
				basicParams.partyBsWhiteList[i],
				basicParams.symbolId,
				basicParams.positionType,
				basicParams.orderType,
				partyBValues,
				basicParams.deadline
			);
			emit ObserverSendQuote(
				msg.sender,
				quoteId,
				basicParams.partyBsWhiteList[i],
				basicParams.symbolId,
				basicParams.positionType,
				basicParams.orderType,
				EncryptedQuoteValues({
					price: observerValues.requestedOpenPrice,
					marketPrice: observerValues.marketPrice,
					quantity: observerValues.quantity,
					cva: observerValues.lockedValues.cva,
					lf: observerValues.lockedValues.lf,
					partyAmm: observerValues.lockedValues.partyAmm,
					partyBmm: observerValues.lockedValues.partyBmm,
					tradingFee: observerValues.tradingFee
				}),
				basicParams.deadline
			);
		}
	}

	/**
	 * @notice Expires the specified quotes.
	 * @param expiredQuoteIds An array of IDs of the quotes to be expired.
	 */
	function expireQuote(uint256[] memory expiredQuoteIds) external whenNotPartyAActionsPaused {
		QuoteStatus result;
		for (uint256 i; i < expiredQuoteIds.length; i++) {
			result = LibQuote.expireQuote(expiredQuoteIds[i]);
			if (result == QuoteStatus.OPENED) {
				emit ExpireQuoteClose(result, expiredQuoteIds[i], QuoteStorage.layout().closeIds[expiredQuoteIds[i]]);
			} else {
				emit ExpireQuoteOpen(result, expiredQuoteIds[i]);
			}
		}
	}

	/**
     * @notice Requests to cancel the specified quote. Two scenarios can occur:
			If the quote has not yet been locked, it will be immediately canceled.
			For a locked quote, the outcome depends on PartyB's decision to either accept the cancellation request or to proceed with opening the position, disregarding the request. 
			If PartyB agrees to cancel, the quote will no longer be accessible for others to interact with. 
			Conversely, if the position has been opened, the user is unable to issue this request.
	 * @param quoteId The ID of the quote to be canceled.
	 */
	function requestToCancelQuote(uint256 quoteId) external whenNotPartyAActionsPaused notSuspended(msg.sender) onlyPartyAOfQuote(quoteId) notLiquidated(quoteId) {
		QuoteStatus result = PartyAFacetImpl.requestToCancelQuote(quoteId);
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		if (result == QuoteStatus.EXPIRED) {
			emit ExpireQuoteOpen(result, quoteId);
		} else if (result == QuoteStatus.CANCELED || result == QuoteStatus.CANCEL_PENDING) {
			emit RequestToCancelQuote(quote.partyA, quote.partyB, result, quoteId);
		}
	}

	/**
	 * @notice User requests to close one of their position with encrypted parameters.
	 * @param quoteId The ID of the quote associated with the position to be closed.
	 * @param encryptedClosePrice The encrypted closing price for the position. In the case of limit orders, this is the price the user wants to close the position at.
	 * 						For market orders, it's more like a price threshold the user's okay with when closing their position. Say, for a random symbol, the market price is $1000.
	 * 						If a user wants to close a short position on this symbol, they might be cool with prices up to $1010
	 * @param encryptedQuantityToClose The encrypted quantity of the position to be closed.
	 * @param orderType  orderType can again be LIMIT or MARKET with the same logic as in SendQuote
	 * @param deadline The deadline for executing the position closure. If 'partyB' doesn't get back to the request within a certain time, then the request will just time out
	 */
	function requestToClosePosition(
		uint256 quoteId,
		itUint256 calldata encryptedClosePrice,
		itUint256 calldata encryptedQuantityToClose,
		OrderType orderType,
		uint256 deadline
	) external whenNotPartyAActionsPaused notSuspended(msg.sender) onlyPartyAOfQuote(quoteId) notLiquidated(quoteId) {
		gtUint256 gtClosePrice = MpcCore.validateCiphertext(encryptedClosePrice);
		gtUint256 gtQuantityToClose = MpcCore.validateCiphertext(encryptedQuantityToClose);
		
		PartyAFacetImpl.requestToClosePosition(quoteId, gtClosePrice, gtQuantityToClose, orderType, deadline);
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		
		// Emit encrypted events for both parties
		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			emit RequestToClosePositionForPartyA(
				quote.partyA,
				quote.partyB,
				quoteId,
				MpcCore.offBoardToUser(gtClosePrice, partyAEncryptionAddress),
				MpcCore.offBoardToUser(gtQuantityToClose, partyAEncryptionAddress),
				orderType,
				deadline,
				QuoteStatus.CLOSE_PENDING,
				quoteLayout.closeIds[quoteId]
			);
		}
		{
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
			emit RequestToClosePositionForPartyB(
				quote.partyA,
				quote.partyB,
				quoteId,
				MpcCore.offBoardToUser(gtClosePrice, partyBEncryptionAddress),
				MpcCore.offBoardToUser(gtQuantityToClose, partyBEncryptionAddress),
				orderType,
				deadline,
				QuoteStatus.CLOSE_PENDING,
				quoteLayout.closeIds[quoteId]
			);
		}
		emit ObserverRequestToClosePosition(
			quote.partyA,
			quote.partyB,
			quoteId,
			LibEncryption.offBoardToObserver(gtClosePrice),
			LibEncryption.offBoardToObserver(gtQuantityToClose),
			orderType,
			deadline,
			QuoteStatus.CLOSE_PENDING,
			quoteLayout.closeIds[quoteId]
		);
	}

	/**
	 * @notice Requests to cancel a pending position closure request.
	 * @param quoteId The ID of the quote associated with the position.
	 */
	function requestToCancelCloseRequest(uint256 quoteId) external whenNotPartyAActionsPaused notSuspended(msg.sender) onlyPartyAOfQuote(quoteId) notLiquidated(quoteId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		QuoteStatus result = PartyAFacetImpl.requestToCancelCloseRequest(quoteId);
		if (result == QuoteStatus.OPENED) {
			emit ExpireQuoteClose(QuoteStatus.OPENED, quoteId, quoteLayout.closeIds[quoteId]);
		} else if (result == QuoteStatus.CANCEL_CLOSE_PENDING) {
			emit RequestToCancelCloseRequest(quote.partyA, quote.partyB, quoteId, QuoteStatus.CANCEL_CLOSE_PENDING, quoteLayout.closeIds[quoteId]);
		}
	}
}
