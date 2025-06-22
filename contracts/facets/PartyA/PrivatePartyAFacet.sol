// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyAFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IPrivatePartyAFacet.sol";
import "../../libraries/LibPrivateQuote.sol";
import "../../storages/SymbolStorage.sol";
import "../../storages/QuoteStorage.sol";

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
		quoteId = PartyAFacetImpl.sendPrivateQuote(
			basicParams.partyBsWhiteList,
			basicParams.symbolId,
			basicParams.positionType,
			basicParams.orderType,
			encryptedParams.encryptedPrice,
			encryptedParams.encryptedQuantity,
			encryptedParams.encryptedCva,
			encryptedParams.encryptedLf,
			encryptedParams.encryptedPartyAmm,
			encryptedParams.encryptedPartyBmm,
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
				MpcCore.offBoardToUser(MpcCore.validateCiphertext(encryptedParams.encryptedQuantity), msg.sender),
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
					MpcCore.offBoardToUser(MpcCore.validateCiphertext(encryptedParams.encryptedQuantity), basicParams.partyBsWhiteList[0]),
					upnlSig.price,
					SymbolStorage.layout().symbols[basicParams.symbolId].tradingFee,
					basicParams.deadline
				);
			}
		}
	}
}
