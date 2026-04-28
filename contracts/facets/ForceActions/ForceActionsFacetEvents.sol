// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/QuoteStorage.sol";

interface ForceActionsFacetEvents {
	event ObserverForceLiquidatePartyB(address liquidator, address partyB, address partyA, ctUint256 partyBAllocatedBalance, ctInt256 upnl);

	event ForceCancelQuote(uint256 quoteId, QuoteStatus quoteStatus);
	event ForceCancelCloseRequest(uint256 quoteId, QuoteStatus quoteStatus, uint256 closeId);
	event ForceClosePositionForPartyA(
		uint256 quoteId,
		address partyA,
		address partyB,
		ctUint256 filledAmount,
		ctUint256 closePrice,
		QuoteStatus quoteStatus,
		uint256 closeId
	);
	event ForceClosePositionForPartyB(
		uint256 quoteId,
		address partyA,
		address partyB,
		ctUint256 filledAmount,
		ctUint256 closePrice,
		QuoteStatus quoteStatus,
		uint256 closeId
	);
	event ObserverForceClosePosition(
		uint256 quoteId,
		address partyA,
		address partyB,
		ctUint256 filledAmount,
		ctUint256 closePrice,
		QuoteStatus quoteStatus,
		uint256 closeId
	);
}
