// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/PrivateQuoteStorage.sol";
import "../storages/MuonStorage.sol";

interface IPrivatePartiesEvents {
	event AcceptCancelRequest(uint256 quoteId, QuoteStatus quoteStatus); // TODO: change to private

	event SendPrivateQuoteForPartyA(
		address partyA,
		uint256 quoteId,
		address[] partyBsWhiteList,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		ctUint256 price,
		ctUint256 marketPrice,
		ctUint256 quantity,
		ctUint256 cva,
		ctUint256 lf,
		ctUint256 partyAmm,
		ctUint256 partyBmm,
		ctUint256 tradingFee,
		uint256 deadline
	);

	event SendPrivateQuoteForPartyB(
		address partyA,
		uint256 quoteId,
		address partyB,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		ctUint256 price,
		ctUint256 marketPrice,
		ctUint256 quantity,
		ctUint256 cva,
		ctUint256 lf,
		ctUint256 partyAmm,
		ctUint256 partyBmm,
		ctUint256 tradingFee,
		uint256 deadline
	);

	event ExpireQuoteOpen(QuoteStatus quoteStatus, uint256 quoteId); // TODO: change to private

	event ExpireQuoteClose(QuoteStatus quoteStatus, uint256 quoteId, uint256 closeId); // TODO: change to private

	event OpenPosition(uint256 quoteId, address partyA, address partyB, uint256 filledAmount, uint256 openedPrice); // TODO: change to private

	event FillCloseRequest(
		uint256 quoteId,
		address partyA,
		address partyB,
		uint256 filledAmount,
		uint256 closedPrice,
		QuoteStatus quoteStatus,
		uint256 closeId
	); // TODO: change to private

	event LiquidatePartyB(address liquidator, address partyB, address partyA, uint256 partyBAllocatedBalance, int256 upnl); // TODO: change to private
}
