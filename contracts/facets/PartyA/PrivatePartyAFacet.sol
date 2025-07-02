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
import "../../storages/SymbolStorage.sol";
import "../../storages/QuoteStorage.sol";

contract PrivatePartyAFacet is Accessibility, Pausable, IPrivatePartyAFacet {
	event PrivateParamsTest(gtUint256 gtPrice, gtUint256 gtQuantity, gtUint256 gtCva, gtUint256 gtLf, gtUint256 gtPartyAmm, gtUint256 gtPartyBmm);

	function privateParamsTest(
		QuoteBasicParams calldata basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig calldata upnlSig
	) external {
		// Validate encrypted inputs without decrypting
		gtUint256 memory gtPrice = MpcCore.validateCiphertext(encryptedParams.encryptedPrice);
		gtUint256 memory gtQuantity = MpcCore.validateCiphertext(encryptedParams.encryptedQuantity);
		gtUint256 memory gtCva = MpcCore.validateCiphertext(encryptedParams.encryptedCva);
		gtUint256 memory gtLf = MpcCore.validateCiphertext(encryptedParams.encryptedLf);
		gtUint256 memory gtPartyAmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyAmm);
		gtUint256 memory gtPartyBmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyBmm);

		emit PrivateParamsTest(gtPrice, gtQuantity, gtCva, gtLf, gtPartyAmm, gtPartyBmm);
	}

	// /**
	//  * @notice Send a Private Quote to the protocol with encrypted parameters. The quote status will be pending.
	//  * @param basicParams Struct containing basic quote parameters
	//  * @param encryptedParams Struct containing all encrypted parameters
	//  * @param upnlSig The Muon signature for user upnl and symbol price
	//  */
	// function sendPrivateQuote(
	// 	QuoteBasicParams calldata basicParams,
	// 	PrivateQuoteParams calldata encryptedParams,
	// 	SingleUpnlAndPriceSig calldata upnlSig
	// ) external whenNotPartyAActionsPaused notLiquidatedPartyA(msg.sender) notSuspended(msg.sender) returns (uint256 quoteId) {
	// 	// Validate encrypted inputs without decrypting
	// 	gtUint256 memory gtPrice = MpcCore.validateCiphertext(encryptedParams.encryptedPrice);
	// 	gtUint256 memory gtQuantity = MpcCore.validateCiphertext(encryptedParams.encryptedQuantity);
	// 	gtUint256 memory gtCva = MpcCore.validateCiphertext(encryptedParams.encryptedCva);
	// 	gtUint256 memory gtLf = MpcCore.validateCiphertext(encryptedParams.encryptedLf);
	// 	gtUint256 memory gtPartyAmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyAmm);
	// 	gtUint256 memory gtPartyBmm = MpcCore.validateCiphertext(encryptedParams.encryptedPartyBmm);

	function sendPrivateQuote(
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

		emit SendPrivateQuotePublic(
			msg.sender,
			quoteId,
			basicParams.partyBsWhiteList,
			basicParams.symbolId,
			basicParams.positionType,
			basicParams.orderType,
			upnlSig.price,
			SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee,
			basicParams.deadline
		);

		{
			// 2. PartyA encrypted event
			emit SendPrivateQuoteForPartyA(
				msg.sender,
				quoteId,
				basicParams.partyBsWhiteList,
				basicParams.symbolId,
				basicParams.positionType,
				basicParams.orderType,
				MpcCore.offBoardToUser(MpcCore.setPublic256(encryptedParams.encryptedQuantity), msg.sender),
				upnlSig.price,
				SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee,
				basicParams.deadline
			);
		}

		{
			// 3. PartyB encrypted event
			if (basicParams.partyBsWhiteList.length == 1) {
				emit SendPrivateQuoteForPartyB(
					msg.sender,
					quoteId,
					basicParams.partyBsWhiteList,
					basicParams.symbolId,
					basicParams.positionType,
					basicParams.orderType,
					MpcCore.offBoardToUser(MpcCore.setPublic256(encryptedParams.encryptedQuantity), basicParams.partyBsWhiteList[0]),
					upnlSig.price,
					SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee,
					basicParams.deadline
				);
			}
		}
	}
}
