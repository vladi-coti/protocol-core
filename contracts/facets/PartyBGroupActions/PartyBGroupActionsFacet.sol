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
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

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
		PartyBQuoteActionsFacetImpl.lockQuote(quoteId, upnlSig);
		gtUint256 gtFilledAmount = MpcCore.validateCiphertext(encryptedParams.encryptedFilledAmount);
		gtUint256 gtOpenedPrice = MpcCore.validateCiphertext(encryptedParams.encryptedOpenedPrice);
		uint256 newId = PartyBPositionActionsFacetImpl.openPosition(quoteId, gtFilledAmount, gtOpenedPrice, pairUpnlSig);

		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		emit LockQuote(quote.partyB, quoteId);

		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		address partyBAddr = LibAccount.getUserEncryptionAddress(quote.partyB);
		emit OpenPositionForPartyA(
			quoteId,
			quote.partyA,
			quote.partyB,
			EncryptedPositionValues(MpcCore.offBoardToUser(gtFilledAmount, partyAAddr), MpcCore.offBoardToUser(gtOpenedPrice, partyAAddr))
		);
		emit OpenPositionForPartyB(
			quoteId,
			quote.partyA,
			quote.partyB,
			EncryptedPositionValues(MpcCore.offBoardToUser(gtFilledAmount, partyBAddr), MpcCore.offBoardToUser(gtOpenedPrice, partyBAddr))
		);

		if (newId != 0) {
			Quote storage newQuote = QuoteStorage.layout().quotes[newId];
			if (newQuote.quoteStatus == QuoteStatus.PENDING) {
				gtUint256 gtPrice = MpcCore.onBoard(newQuote.requestedOpenPrice.ciphertext);
				gtUint256 gtQuantity = MpcCore.onBoard(newQuote.quantity.ciphertext);
				address newQuotePartyAAddr = LibAccount.getUserEncryptionAddress(newQuote.partyA);
				gtUint256 gtMarketPrice = MpcCore.setPublic256(pairUpnlSig.price);
				gtUint256 gtTradingFee = MpcCore.setPublic256(SymbolStorage.layout().symbols[newQuote.symbolId].tradingFee);
				GarbledLockedValues memory gtLocked = newQuote.lockedValues.onBoard();
				emit SendQuoteForPartyA(
					newQuote.partyA,
					newId,
					newQuote.partyBsWhiteList,
					newQuote.symbolId,
					newQuote.positionType,
					newQuote.orderType,
					EncryptedQuoteValues(
						MpcCore.offBoardToUser(gtPrice, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtMarketPrice, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtQuantity, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtLocked.cva, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtLocked.lf, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtLocked.partyAmm, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtLocked.partyBmm, newQuotePartyAAddr),
						MpcCore.offBoardToUser(gtTradingFee, newQuotePartyAAddr)
					),
					newQuote.deadline
				);
				for (uint256 i = 0; i < newQuote.partyBsWhiteList.length; i++) {
					address newQuotePartyBAddr = LibAccount.getUserEncryptionAddress(newQuote.partyBsWhiteList[i]);
					emit SendQuoteForPartyB(
						newQuote.partyA,
						newId,
						newQuote.partyBsWhiteList[i],
						newQuote.symbolId,
						newQuote.positionType,
						newQuote.orderType,
						EncryptedQuoteValues(
							MpcCore.offBoardToUser(gtPrice, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtMarketPrice, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtQuantity, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtLocked.cva, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtLocked.lf, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtLocked.partyAmm, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtLocked.partyBmm, newQuotePartyBAddr),
							MpcCore.offBoardToUser(gtTradingFee, newQuotePartyBAddr)
						),
						newQuote.deadline
					);
				}
			} else if (newQuote.quoteStatus == QuoteStatus.CANCELED) {
				emit AcceptCancelRequest(newQuote.id, QuoteStatus.CANCELED);
			}
		}
	}
}
