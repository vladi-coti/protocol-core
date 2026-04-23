// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../ForceActions/ForceActionsFacetEvents.sol";
import "../PartyBPositionActions/IPartyBPositionActionsEvents.sol";

interface IRecoveryActionsFacet is ForceActionsFacetEvents, IPartyBPositionActionsEvents {
	function forceCancelQuote(uint256 quoteId) external;

	function emergencyClosePosition(uint256 quoteId, PairUpnlAndPriceSig memory upnlSig) external;
}
