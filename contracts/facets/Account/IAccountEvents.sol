// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

interface IAccountEvents {
	event Deposit(address sender, address user, uint256 amount);
	event Withdraw(address sender, address user, uint256 amount);
	event AllocatePartyA(address user, uint256 amount, ctUint256 newAllocatedBalance);
	event DeallocatePartyA(address user, uint256 amount, ctUint256 newAllocatedBalance);
	event InternalTransfer(address sender, address user, ctUint256 userNewAllocatedBalance, uint256 amount);
	event AllocateForPartyB(address partyB, address partyA, uint256 amount, ctUint256 newAllocatedBalance);
	event DeallocateForPartyB(address partyB, address partyA, uint256 amount, ctUint256 newAllocatedBalance);
	event TransferAllocation(
		uint256 amount,
		address origin,
		ctUint256 originNewAllocatedBalance,
		address recipient,
		ctUint256 recipientNewAllocatedBalance
	);
	event DepositToReserveVault(address sender, address partyB, uint256 amount);
	event WithdrawFromReserveVault(address partyB, uint256 amount);
	event ClaimFeeCollectorBalance(address feeCollector, uint256 amount, ctUint256 newFeeCollectorBalance);
    event EncryptionAddressChanged(address user, address fromAddress, address toAddress);
}
