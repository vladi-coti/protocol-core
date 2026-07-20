// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../../storages/MAStorage.sol";
import "../../libraries/LibAccount.sol";
import "../../utils/Pausable.sol";
import "../../utils/Accessibility.sol";
import "./ILiquidationEvents.sol";
import "./ILiquidationResolutionFacet.sol";
import "./LiquidationFacetImpl.sol";

contract LiquidationResolutionFacet is Pausable, Accessibility, ILiquidationResolutionFacet {
	function settlePartyALiquidation(address partyA, address[] memory partyBs) external whenNotLiquidationPaused {
		(gtInt256[] memory settleAmounts, bytes memory liquidationId) = LiquidationFacetImpl.settlePartyALiquidation(partyA, partyBs);
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		ctInt256[] memory encryptedSettleAmounts = new ctInt256[](settleAmounts.length);
		for (uint256 i = 0; i < settleAmounts.length; i++) {
			encryptedSettleAmounts[i] = MpcCore.offBoardToUser(settleAmounts[i], partyAEncryptionAddress);
		}
		emit SettlePartyALiquidation(partyA, partyBs, encryptedSettleAmounts, liquidationId);
		if (!MAStorage.layout().liquidationStatus[partyA]) {
			emit FullyLiquidatedPartyA(partyA, liquidationId);
		}
	}

	function resolveLiquidationDispute(
		address partyA,
		address[] memory partyBs,
		itInt256[] calldata amounts,
		bool disputed
	) external onlyRole(LibAccessibility.DISPUTE_ROLE) {
		require(partyBs.length == amounts.length, "LiquidationFacet: Invalid length");
		gtInt256[] memory gtAmounts = new gtInt256[](amounts.length);
		for (uint256 i = 0; i < amounts.length; i++) {
			gtAmounts[i] = MpcCore.validateCiphertext(amounts[i]);
		}
		bytes memory liquidationId = LiquidationFacetImpl.resolveLiquidationDispute(partyA, partyBs, gtAmounts, disputed);
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		ctInt256[] memory encryptedAmounts = new ctInt256[](gtAmounts.length);
		for (uint256 i = 0; i < gtAmounts.length; i++) {
			encryptedAmounts[i] = MpcCore.offBoardToUser(gtAmounts[i], partyAEncryptionAddress);
		}
		emit ResolveLiquidationDispute(partyA, partyBs, encryptedAmounts, disputed, liquidationId);
	}
}
