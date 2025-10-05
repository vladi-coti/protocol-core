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

contract PartyAFacet is Accessibility, Pausable, IPartyAFacet {
	event PrivateParamsTest(uint256 price);

	function privateParamsTest(
		QuoteBasicParams calldata basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external returns (gtUint256) {
		gtUint256 gtPrice = MpcCore.validateCiphertext(encryptedParams.encryptedPrice);
		gtUint256 gtQuantity = MpcCore.validateCiphertext(encryptedParams.encryptedQuantity);
		gtUint256 gtCva = MpcCore.validateCiphertext(encryptedParams.encryptedCva);
		gtUint256 gtLf = MpcCore.validateCiphertext(encryptedParams.encryptedLf);
		gtUint256 gtPartyAmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyAmm);
		gtUint256 gtPartyBmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyBmm);

		emit PrivateParamsTest(MpcCore.decrypt(gtPrice));

		return gtPrice;
	}

	function privateParamsTestPlaintext(
		QuoteBasicParams calldata basicParams,
		TempQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external returns (gtUint256) {
		gtUint256 gtPrice = MpcCore.setPublic256(encryptedParams.encryptedPrice);
		gtUint256 gtQuantity = MpcCore.setPublic256(encryptedParams.encryptedQuantity);
		gtUint256 gtCva = MpcCore.setPublic256(encryptedParams.encryptedCva);
		gtUint256 gtLf = MpcCore.setPublic256(encryptedParams.encryptedLf);
		gtUint256 gtPartyAmm = MpcCore.setPublic256(encryptedParams.encryptedPartyAmm);
		gtUint256 gtPartyBmm = MpcCore.setPublic256(encryptedParams.encryptedPartyBmm);

		emit PrivateParamsTest(MpcCore.decrypt(gtPrice));

		return gtPrice;
	}

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
		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
			EncryptedQuoteValues memory partyAValues = EncryptedQuoteValues({
				price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
				marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
				quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
				cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyAEncryptionAddress),
				lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyAEncryptionAddress),
				partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyAEncryptionAddress),
				partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyAEncryptionAddress),
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
		}
		{
			for (uint256 i = 0; i < basicParams.partyBsWhiteList.length; i++) {
				address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(basicParams.partyBsWhiteList[i]);
				EncryptedQuoteValues memory partyBValues = EncryptedQuoteValues({
					price: MpcCore.offBoardToUser(gtPrice, partyBEncryptionAddress),
					marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyBEncryptionAddress),
					quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
					cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyBEncryptionAddress),
					lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyBEncryptionAddress),
					partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyBEncryptionAddress),
					partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyBEncryptionAddress),
					tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyBEncryptionAddress)
				});
				emit SendQuoteForPartyB(
					msg.sender,
					quoteId,
					partyBEncryptionAddress,
					basicParams.symbolId,
					basicParams.positionType,
					basicParams.orderType,
					partyBValues,
					basicParams.deadline
				);
			}
		}
	}

	// TEMP function to send private quote with plaintext parameters
	function sendQuotePlaintext(
		QuoteBasicParams calldata basicParams,
		TempQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external whenNotPartyAActionsPaused notLiquidatedPartyA(msg.sender) notSuspended(msg.sender) returns (uint256 quoteId) {
		// FIXME: Remove this once the proper way to handling encrypted parameters is fixed
		gtUint256 gtPrice = MpcCore.setPublic256(encryptedParams.encryptedPrice);
		gtUint256 gtQuantity = MpcCore.setPublic256(encryptedParams.encryptedQuantity);
		gtUint256 gtCva = MpcCore.setPublic256(encryptedParams.encryptedCva);
		gtUint256 gtLf = MpcCore.setPublic256(encryptedParams.encryptedLf);
		gtUint256 gtPartyAmm = MpcCore.setPublic256(encryptedParams.encryptedPartyAmm);
		gtUint256 gtPartyBmm = MpcCore.setPublic256(encryptedParams.encryptedPartyBmm);

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

		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
			EncryptedQuoteValues memory partyAValues = EncryptedQuoteValues({
				price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
				marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
				quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
				cva: MpcCore.offBoardToUser(gtCva, partyAEncryptionAddress),
				lf: MpcCore.offBoardToUser(gtLf, partyAEncryptionAddress),
				partyAmm: MpcCore.offBoardToUser(gtPartyAmm, partyAEncryptionAddress),
				partyBmm: MpcCore.offBoardToUser(gtPartyBmm, partyAEncryptionAddress),
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
		}
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
			EncryptedQuoteValues memory partyAValues = EncryptedQuoteValues({
				price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
				marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
				quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
				cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyAEncryptionAddress),
				lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyAEncryptionAddress),
				partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyAEncryptionAddress),
				partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyAEncryptionAddress),
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
		}
		{
			for (uint256 i = 0; i < basicParams.partyBsWhiteList.length; i++) {
				address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(basicParams.partyBsWhiteList[i]);
				EncryptedQuoteValues memory partyBValues = EncryptedQuoteValues({
					price: MpcCore.offBoardToUser(gtPrice, partyBEncryptionAddress),
					marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyBEncryptionAddress),
					quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
					cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyBEncryptionAddress),
					lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyBEncryptionAddress),
					partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyBEncryptionAddress),
					partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyBEncryptionAddress),
					tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyBEncryptionAddress)
				});
				emit SendQuoteForPartyB(
					msg.sender,
					quoteId,
					partyBEncryptionAddress,
					basicParams.symbolId,
					basicParams.positionType,
					basicParams.orderType,
					partyBValues,
					basicParams.deadline
				);
			}
		}
	}

	/**
	 * @notice Expires the specified quotes.
	 * @param expiredQuoteIds An array of IDs of the quotes to be expired.
	 */
	function expireQuote(uint256[] memory expiredQuoteIds) external whenNotPartyAActionsPaused {
		QuoteStatus result;
		for (uint8 i; i < expiredQuoteIds.length; i++) {
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
	function requestToCancelQuote(uint256 quoteId) external whenNotPartyAActionsPaused onlyPartyAOfQuote(quoteId) notLiquidated(quoteId) {
		QuoteStatus result = PartyAFacetImpl.requestToCancelQuote(quoteId);
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		if (result == QuoteStatus.EXPIRED) {
			emit ExpireQuoteOpen(result, quoteId);
		} else if (result == QuoteStatus.CANCELED || result == QuoteStatus.CANCEL_PENDING) {
			emit RequestToCancelQuote(quote.partyA, quote.partyB, result, quoteId);
		}
	}

	/**
	 * @notice User requests to close one of their position.
	 * @param quoteId The ID of the quote associated with the position to be closed.
	 * @param closePrice The closing price for the position. In the case of limit orders, this is the price the user wants to close the position at.
	 * 						For market orders, it's more like a price threshold the user's okay with when closing their position. Say, for a random symbol, the market price is $1000.
	 * 						If a user wants to close a short position on this symbol, they might be cool with prices up to $1010
	 * @param quantityToClose The quantity of the position to be closed.
	 * @param orderType  orderType can again be LIMIT or MARKET with the same logic as in SendQuote
	 * @param deadline The deadline for executing the position closure. If 'partyB' doesn't get back to the request within a certain time, then the request will just time out
	 */
	function requestToClosePosition(
		uint256 quoteId,
		uint256 closePrice,
		uint256 quantityToClose,
		OrderType orderType,
		uint256 deadline
	) external whenNotPartyAActionsPaused onlyPartyAOfQuote(quoteId) notLiquidated(quoteId) {
		PartyAFacetImpl.requestToClosePosition(quoteId, closePrice, quantityToClose, orderType, deadline);
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];
		emit RequestToClosePosition(
			quote.partyA,
			quote.partyB,
			quoteId,
			closePrice,
			quantityToClose,
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
	function requestToCancelCloseRequest(uint256 quoteId) external whenNotPartyAActionsPaused onlyPartyAOfQuote(quoteId) notLiquidated(quoteId) {
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
