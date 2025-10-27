// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/QuoteStorage.sol";
import "../storages/MuonStorage.sol";

interface IPartiesEvents {
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

	event ExpireQuoteOpen(QuoteStatus quoteStatus, uint256 quoteId);

	event ExpireQuoteClose(QuoteStatus quoteStatus, uint256 quoteId, uint256 closeId);

	event OpenPositionForPartyA(
		uint256 quoteId,
		address partyA,
		address partyB,
		EncryptedPositionValues values
	);

	event OpenPositionForPartyB(
		uint256 quoteId,
		address partyA,
		address partyB,
		EncryptedPositionValues values
	);

	event FillCloseRequestForPartyA(
		uint256 quoteId,
		address partyA,
		address partyB,
		EncryptedPositionValues values,
		QuoteStatus quoteStatus,
		uint256 closeId
	);

	event FillCloseRequestForPartyB(
		uint256 quoteId,
		address partyA,
		address partyB,
		EncryptedPositionValues values,
		QuoteStatus quoteStatus,
		uint256 closeId
	);

	event LiquidatePartyB(address liquidator, address partyB, address partyA, uint256 partyBAllocatedBalance, int256 upnl);
}
