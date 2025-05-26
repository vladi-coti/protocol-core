// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/MuonStorage.sol";
import "./IPartyBPositionActionsEvents.sol";

interface IPartyBPositionActionsPrivateFacet is IPartyBPositionActionsEvents {
	/**
	 * @notice Opens a position with private variable support
	 * @param quoteId The ID of the quote for which the position is opened
	 * @param filledAmount The amount to fill
	 * @param openedPrice The opened price for the position
	 * @param upnlSig The Muon signature containing PairUpnlAndPriceSig data
	 * @param usePrivateMode Whether to enable private variables for this position
	 */
	function openPositionWithPrivacy(
		uint256 quoteId,
		uint256 filledAmount,
		uint256 openedPrice,
		PairUpnlAndPriceSig memory upnlSig,
		bool usePrivateMode
	) external;
}
