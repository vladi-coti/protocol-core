// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPartyAEvents.sol";
import "../../storages/MuonStorage.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

struct PrivateQuoteParams {
	itUint256 encryptedPrice;
	itUint256 encryptedQuantity;
	itUint256 encryptedCva;
	itUint256 encryptedLf;
	itUint256 encryptedPartyAmm;
	itUint256 encryptedPartyBmm;
}

struct QuoteBasicParams {
	address[] partyBsWhiteList;
	uint256 symbolId;
	PositionType positionType;
	OrderType orderType;
	uint256 maxFundingRate;
	uint256 deadline;
	address affiliate;
}

interface IPrivatePartyAFacet is IPartyAEvents {
	function sendPrivateQuote(
		QuoteBasicParams memory basicParams,
		PrivateQuoteParams calldata encryptedParams,
		SingleUpnlAndPriceSig memory upnlSig
	) external returns (uint256);
}
