// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPartyBGroupActionsFacet.sol";
import "../PartyBPositionActions/PartyBPositionActionsFacetImpl.sol";
import "../PartyBQuoteActions/PartyBQuoteActionsFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PartyBGroupActionsFacet is Accessibility, Pausable, IPartyBGroupActionsFacet {

	/**
	 * @notice Locks and opens the specified quote with the provided details and signatures.
	 * @param quoteId The ID of the quote to be locked and opened.
	 * @param encryptedParams Struct containing encrypted filledAmount and openedPrice parameters.
	 * @param upnlSig The Muon signature containing the single UPNL value used to lock the quote.
	 * @param pairUpnlSig The Muon signature containing the pair UPNL and price values used to open the position.
	 */
	function lockAndOpenQuote(
		uint256 quoteId,
		PrivateOpenPositionParams calldata encryptedParams,
		SingleUpnlSig memory upnlSig,
		PairUpnlAndPriceSig memory pairUpnlSig
	) external override whenNotPartyBActionsPaused onlyPartyB notLiquidated(quoteId) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		PartyBQuoteActionsFacetImpl.lockQuote(quoteId, upnlSig);
		emit LockQuote(quote.partyB, quoteId);
		gtUint256 gtFilledAmount = MpcCore.validateCiphertext(encryptedParams.encryptedFilledAmount);
		gtUint256 gtOpenedPrice = MpcCore.validateCiphertext(encryptedParams.encryptedOpenedPrice);
		uint256 newId = PartyBPositionActionsFacetImpl.openPosition(quoteId, gtFilledAmount, gtOpenedPrice, pairUpnlSig);
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
						msg.sender,
						quoteId,
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
							msg.sender,
							quoteId,
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
}
