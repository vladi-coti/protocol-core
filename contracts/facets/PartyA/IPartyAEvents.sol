// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/QuoteStorage.sol";
import "../../interfaces/IPartiesEvents.sol";

interface IPartyAEvents is IPartiesEvents {
	event ObserverSendQuote(
		address partyA,
		uint256 quoteId,
		address partyB,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		EncryptedQuoteValues values,
		uint256 deadline
	);

	event RequestToCancelQuote(address partyA, address partyB, QuoteStatus quoteStatus, uint256 quoteId);
	event RequestToClosePositionForPartyA(
		address partyA,
		address partyB,
		uint256 quoteId,
		ctUint256 closePrice,
		ctUint256 quantityToClose,
		OrderType orderType,
		uint256 deadline,
		QuoteStatus quoteStatus,
		uint256 closeId
	);
	event RequestToClosePositionForPartyB(
		address partyA,
		address partyB,
		uint256 quoteId,
		ctUint256 closePrice,
		ctUint256 quantityToClose,
		OrderType orderType,
		uint256 deadline,
		QuoteStatus quoteStatus,
		uint256 closeId
	);
	event ObserverRequestToClosePosition(
		address partyA,
		address partyB,
		uint256 quoteId,
		ctUint256 closePrice,
		ctUint256 quantityToClose,
		OrderType orderType,
		uint256 deadline,
		QuoteStatus quoteStatus,
		uint256 closeId
	);
	event RequestToCancelCloseRequest(address partyA, address partyB, uint256 quoteId, QuoteStatus quoteStatus, uint256 closeId);
}
