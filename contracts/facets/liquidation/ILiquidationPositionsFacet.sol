// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/MuonStorage.sol";
import "./ILiquidationEvents.sol";

interface ILiquidationPositionsFacet is ILiquidationEvents {
	function liquidatePendingPositionsPartyA(address partyA) external;

	function liquidatePositionsPartyA(address partyA, uint256[] memory quoteIds) external;

	function liquidatePositionsPartyB(address partyB, address partyA, QuotePriceSig memory priceSig) external;
}
