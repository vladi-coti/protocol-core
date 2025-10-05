// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPartyAEvents.sol";
import "../../storages/MuonStorage.sol";

struct TempQuoteParams { // TODO: remove this once the proper way to handling encrypted parameters is fixed
	uint256 encryptedPrice;
	uint256 encryptedQuantity;
	uint256 encryptedCva;
	uint256 encryptedLf;
	uint256 encryptedPartyAmm;
	uint256 encryptedPartyBmm;
}

interface IPartyAFacet is IPartyAEvents {
	function sendQuote(
		QuoteBasicParams memory basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig memory upnlSig
	) external returns (uint256 quoteId);

	function sendQuotePlaintext(
		QuoteBasicParams memory basicParams,
		TempQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig memory upnlSig
	) external returns (uint256 quoteId);

	function expireQuote(uint256[] memory expiredQuoteIds) external;

	function requestToCancelQuote(uint256 quoteId) external;

	function requestToClosePosition(uint256 quoteId, uint256 closePrice, uint256 quantityToClose, OrderType orderType, uint256 deadline) external;

	function requestToCancelCloseRequest(uint256 quoteId) external;
}
