// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../PartyBQuoteActions/IPartyBQuoteActionsEvents.sol";
import "../PartyBPositionActions/PartyBPositionActionsFacetImpl.sol";
import "../PartyBQuoteActions/PartyBQuoteActionsFacetImpl.sol";

library PartyBGroupActionsFacetImpl {
	event LockQuote(address partyB, uint256 quoteId);
	event AcceptCancelRequest(uint256 quoteId, QuoteStatus quoteStatus);
	event SendQuoteForPartyA(
		address partyA,
		uint256 quoteId,
		address[] partyBsWhiteList,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		EncryptedQuoteValues values,
		uint256 deadline
	);
	event SendQuoteForPartyB(
		address partyA,
		uint256 quoteId,
		address partyB,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		EncryptedQuoteValues values,
		uint256 deadline
	);
	event OpenPositionForPartyA(uint256 quoteId, address partyA, address partyB, EncryptedPositionValues values);
	event OpenPositionForPartyB(uint256 quoteId, address partyA, address partyB, EncryptedPositionValues values);

	function lockAndOpenQuote(
		uint256 quoteId,
		PrivateOpenPositionParams calldata encryptedParams,
		SingleUpnlSig memory upnlSig,
		PairUpnlAndPriceSig memory pairUpnlSig
	) public {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		PartyBQuoteActionsFacetImpl.lockQuote(quoteId, upnlSig);
		emit LockQuote(quote.partyB, quoteId);
		gtUint256 gtFilledAmount = MpcCore.validateCiphertext(encryptedParams.encryptedFilledAmount);
		gtUint256 gtOpenedPrice = MpcCore.validateCiphertext(encryptedParams.encryptedOpenedPrice);
		uint256 newId = PartyBPositionActionsFacetImpl.openPosition(quoteId, gtFilledAmount, gtOpenedPrice, pairUpnlSig);
		{
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyA);
			ctUint256 memory filledAmount = MpcCore.offBoardToUser(gtFilledAmount, partyAEncryptionAddress);
			ctUint256 memory openedPrice = MpcCore.offBoardToUser(gtOpenedPrice, partyAEncryptionAddress);
			emit OpenPositionForPartyA(quoteId, quote.partyA, quote.partyB, EncryptedPositionValues(filledAmount, openedPrice));
		}
		{
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
			ctUint256 memory filledAmount = MpcCore.offBoardToUser(gtFilledAmount, partyBEncryptionAddress);
			ctUint256 memory openedPrice = MpcCore.offBoardToUser(gtOpenedPrice, partyBEncryptionAddress);
			emit OpenPositionForPartyB(quoteId, quote.partyA, quote.partyB, EncryptedPositionValues(filledAmount, openedPrice));
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
						marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(pairUpnlSig.price), partyAEncryptionAddress),
						quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
						cva: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.cva.ciphertext), partyAEncryptionAddress),
						lf: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.lf.ciphertext), partyAEncryptionAddress),
						partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyAmm.ciphertext), partyAEncryptionAddress),
						partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyBmm.ciphertext), partyAEncryptionAddress),
						tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[newQuote.symbolId].tradingFee), partyAEncryptionAddress)
					});
					emit SendQuoteForPartyA(
						newQuote.partyA,
						newQuote.id,
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
							marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(pairUpnlSig.price), partyBEncryptionAddress),
							quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
							cva: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.cva.ciphertext), partyBEncryptionAddress),
							lf: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.lf.ciphertext), partyBEncryptionAddress),
							partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyAmm.ciphertext), partyBEncryptionAddress),
							partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(newQuote.lockedValues.partyBmm.ciphertext), partyBEncryptionAddress),
							tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[newQuote.symbolId].tradingFee), partyBEncryptionAddress)
						});
						emit SendQuoteForPartyB(
							newQuote.partyA,
							newQuote.id,
							newQuote.partyBsWhiteList[i],
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
}
