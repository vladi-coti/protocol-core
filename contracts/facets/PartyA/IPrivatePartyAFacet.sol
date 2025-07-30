// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPrivatePartyAEvents.sol";
import "../../storages/MuonStorage.sol";

struct PrivateQuoteParams {
	itUint256 encryptedPrice;
	itUint256 encryptedQuantity;
	itUint256 encryptedCva;
	itUint256 encryptedLf;
	itUint256 encryptedPartyAmm;
	itUint256 encryptedPartyBmm;
}

struct TempQuoteParams { // TODO: remove this once the proper way to handling encrypted parameters is fixed
	uint256 encryptedPrice;
	uint256 encryptedQuantity;
	uint256 encryptedCva;
	uint256 encryptedLf;
	uint256 encryptedPartyAmm;
	uint256 encryptedPartyBmm;
}

struct QuoteBasicParams {
	address[] partyBsWhiteList;
	uint256 symbolId;
	PrivatePositionType positionType;
	PrivateOrderType orderType;
	uint256 maxFundingRate;
	uint256 deadline;
	address affiliate;
}

interface IPrivatePartyAFacet is IPrivatePartyAEvents {
	function sendPrivateQuote(
		QuoteBasicParams memory basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig memory upnlSig
	) external returns (uint256);

	function sendPrivateQuotePlaintext(
		QuoteBasicParams memory basicParams,
		TempQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig memory upnlSig
	) external returns (uint256);
}
