// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PrivatePartyAFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IPrivatePartyAFacet.sol";
import "../../libraries/LibPrivateQuote.sol";
import "../../libraries/LibPrivateAccount.sol";
import "../../storages/SymbolStorage.sol";
import "../../storages/PrivateQuoteStorage.sol";

contract PrivatePartyAFacet is Accessibility, Pausable, IPrivatePartyAFacet {
	/**
	 * @notice Send a Private Quote to the protocol with encrypted parameters. The quote status will be pending.
	 * @param basicParams Struct containing basic quote parameters
	 * @param encryptedParams Struct containing all encrypted parameters
	 * @param upnlSig The Muon signature for user upnl and symbol price
	 */
	function sendPrivateQuote(
		QuoteBasicParams calldata basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external whenNotPartyAActionsPaused notLiquidatedPartyA(msg.sender) notSuspended(msg.sender) returns (uint256 quoteId) {
		gtUint256 memory gtPrice = MpcCore.validateCiphertext(encryptedParams.encryptedPrice);
		gtUint256 memory gtQuantity = MpcCore.validateCiphertext(encryptedParams.encryptedQuantity);
		gtUint256 memory gtCva = MpcCore.validateCiphertext(encryptedParams.encryptedCva);
		gtUint256 memory gtLf = MpcCore.validateCiphertext(encryptedParams.encryptedLf);
		gtUint256 memory gtPartyAmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyAmm);
		gtUint256 memory gtPartyBmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyBmm);

		quoteId = PrivatePartyAFacetImpl.sendPrivateQuote(
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
		
		PrivateQuote storage quote = PrivateQuoteStorage.layout().quotes[quoteId];
		{
			address partyAEncryptionAddress = LibPrivateAccount.getUserEncryptionAddress(msg.sender);
			IPrivatePartiesEvents.EncryptedQuoteValues memory partyAValues = IPrivatePartiesEvents.EncryptedQuoteValues({
				price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
				marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
				quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
				cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyAEncryptionAddress),
				lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyAEncryptionAddress),
				partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyAEncryptionAddress),
				partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyAEncryptionAddress),
				tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyAEncryptionAddress)
			});
			emit SendPrivateQuoteForPartyA(
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
				address partyBEncryptionAddress = LibPrivateAccount.getUserEncryptionAddress(basicParams.partyBsWhiteList[i]);
				IPrivatePartiesEvents.EncryptedQuoteValues memory partyBValues = IPrivatePartiesEvents.EncryptedQuoteValues({
					price: MpcCore.offBoardToUser(gtPrice, partyBEncryptionAddress),
					marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyBEncryptionAddress),
					quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
					cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyBEncryptionAddress),
					lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyBEncryptionAddress),
					partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyBEncryptionAddress),
					partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyBEncryptionAddress),
					tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyBEncryptionAddress)
				});
				emit SendPrivateQuoteForPartyB(
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
	function sendPrivateQuotePlaintext(
		QuoteBasicParams calldata basicParams,
		TempQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external whenNotPartyAActionsPaused notLiquidatedPartyA(msg.sender) notSuspended(msg.sender) returns (uint256 quoteId) {
		// FIXME: Remove this once the proper way to handling encrypted parameters is fixed
		gtUint256 memory gtPrice = MpcCore.setPublic256(encryptedParams.encryptedPrice);
		gtUint256 memory gtQuantity = MpcCore.setPublic256(encryptedParams.encryptedQuantity);
		gtUint256 memory gtCva = MpcCore.setPublic256(encryptedParams.encryptedCva);
		gtUint256 memory gtLf = MpcCore.setPublic256(encryptedParams.encryptedLf);
		gtUint256 memory gtPartyAmm = MpcCore.setPublic256(encryptedParams.encryptedPartyAmm);
		gtUint256 memory gtPartyBmm = MpcCore.setPublic256(encryptedParams.encryptedPartyBmm);

		quoteId = PrivatePartyAFacetImpl.sendPrivateQuote(
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
		PrivateQuote storage quote = PrivateQuoteStorage.layout().quotes[quoteId];
		{
			address partyAEncryptionAddress = LibPrivateAccount.getUserEncryptionAddress(msg.sender);
			IPrivatePartiesEvents.EncryptedQuoteValues memory partyAValues = IPrivatePartiesEvents.EncryptedQuoteValues({
				price: MpcCore.offBoardToUser(gtPrice, partyAEncryptionAddress),
				marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyAEncryptionAddress),
				quantity: MpcCore.offBoardToUser(gtQuantity, partyAEncryptionAddress),
				cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyAEncryptionAddress),
				lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyAEncryptionAddress),
				partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyAEncryptionAddress),
				partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyAEncryptionAddress),
				tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyAEncryptionAddress)
			});
			emit SendPrivateQuoteForPartyA(
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
				address partyBEncryptionAddress = LibPrivateAccount.getUserEncryptionAddress(basicParams.partyBsWhiteList[i]);
				IPrivatePartiesEvents.EncryptedQuoteValues memory partyBValues = IPrivatePartiesEvents.EncryptedQuoteValues({
					price: MpcCore.offBoardToUser(gtPrice, partyBEncryptionAddress),
					marketPrice: MpcCore.offBoardToUser(MpcCore.setPublic256(upnlSig.price), partyBEncryptionAddress),
					quantity: MpcCore.offBoardToUser(gtQuantity, partyBEncryptionAddress),
					cva: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.cva.ciphertext), partyBEncryptionAddress),
					lf: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.lf.ciphertext), partyBEncryptionAddress),
					partyAmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyAmm.ciphertext), partyBEncryptionAddress),
					partyBmm: MpcCore.offBoardToUser(MpcCore.onBoard(quote.lockedValues.partyBmm.ciphertext), partyBEncryptionAddress),
					tradingFee: MpcCore.offBoardToUser(MpcCore.setPublic256(SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee), partyBEncryptionAddress)
				});
				emit SendPrivateQuoteForPartyB(
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
}
