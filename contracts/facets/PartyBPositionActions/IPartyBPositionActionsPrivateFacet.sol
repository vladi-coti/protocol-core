// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/MuonStorage.sol";
import "./IPartyBPositionActionsEvents.sol";
import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

interface IPartyBPositionActionsPrivateFacet is IPartyBPositionActionsEvents {
	/**
	 * @notice Opens a position with private variable support
	 * @param quoteId The ID of the quote for which the position is opened
	 * @param filledAmount The amount to fill (encrypted)
	 * @param openedPrice The opened price for the position
	 * @param upnlSig The Muon signature containing PairUpnlAndPriceSig data
	 */
	function openPositionWithPrivacy(
		uint256 quoteId,
		itUint256 calldata filledAmount,
		uint256 openedPrice,
		PairUpnlAndPriceSig memory upnlSig
	) external;
}
