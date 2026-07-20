// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./ILiquidationEvents.sol";

interface ILiquidationResolutionFacet is ILiquidationEvents {
	function settlePartyALiquidation(address partyA, address[] memory partyBs) external;

	function resolveLiquidationDispute(address partyA, address[] memory partyBs, itInt256[] calldata amounts, bool disputed) external;
}
