// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IAccountFacet.sol";
import "./AccountFacetImpl.sol";
import "../../storages/AccountStorage.sol";

contract AccountManagementFacet is Accessibility, Pausable, IAccountEvents {
	/// @notice Allows transferring the balance of partyB to emergency reserve vault.
	/// @param amount The precise amount of collateral to be transferred to emergency reserve vault, specified in 18 decimals.
	function depositToReserveVault(uint256 amount, address partyB) external whenNotPartyBActionsPaused notSuspended(msg.sender) notSuspended(partyB) {
		AccountFacetImpl.depositToReserveVault(amount, partyB);
		emit DepositToReserveVault(msg.sender, partyB, amount);
	}

	/// @notice Allows transferring the balance of partyB in emergency reserve vault to balance.
	/// @param amount The precise amount of collateral to be transferred from emergency reserve vault, specified in 18 decimals.
	function withdrawFromReserveVault(uint256 amount) external whenNotPartyBActionsPaused notSuspended(msg.sender) {
		AccountFacetImpl.withdrawFromReserveVault(amount);
		emit WithdrawFromReserveVault(msg.sender, amount);
	}

	/// @notice Moves claimed protocol fee accruals into the caller's withdrawable balance.
	/// @param amount The amount to claim, specified in 18 decimals.
	function claimFeeCollectorBalance(uint256 amount) external whenNotAccountingPaused notSuspended(msg.sender) {
		AccountFacetImpl.claimFeeCollectorBalance(amount);
		emit ClaimFeeCollectorBalance(msg.sender, amount, AccountStorage.layout().encryptedFeeCollectorBalances[msg.sender].userCiphertext);
	}
}
