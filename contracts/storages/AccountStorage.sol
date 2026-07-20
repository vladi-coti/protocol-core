// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../libraries/LibLockedValues.sol";

enum LiquidationType {
	NONE,
	NORMAL,
	LATE,
	OVERDUE
}

struct SettlementState {
	utInt256 actualAmount;
	utInt256 expectedAmount;
	utUint256 cva;
	bool pending;
}

struct ObserverSettlementState {
	ctInt256 actualAmount;
	ctInt256 expectedAmount;
	ctUint256 cva;
}

struct LiquidationDetail {
	bytes liquidationId;
	LiquidationType liquidationType;
	utInt256 upnl;
	utInt256 totalUnrealizedLoss;
	/// @dev M-47 husk — always 0. Real value: `encryptedLiquidationDeficit` / `liquidationDeficitOfPartyA`.
	uint256 deficit;
	/// @dev M-47 husk — always 0. Real value: `encryptedLiquidationFee` / `liquidationFeeOfPartyA`.
	uint256 liquidationFee;
	uint256 timestamp;
	uint256 involvedPartyBCounts;
	/// @dev M-47 husk — always 0. Accumulated UPNL lives in encrypted settlement state.
	int256 partyAAccumulatedUpnl;
	bool disputed;
	uint256 liquidationTimestamp;
}

/// @dev Public view shape for liquidation state — omits M-47 plaintext husks.
struct ViewLiquidationDetail {
	bytes liquidationId;
	LiquidationType liquidationType;
	utInt256 upnl;
	utInt256 totalUnrealizedLoss;
	uint256 timestamp;
	uint256 involvedPartyBCounts;
	bool disputed;
	uint256 liquidationTimestamp;
}

struct Price {
	uint256 price;
	uint256 timestamp;
}

library AccountStorage {
	bytes32 internal constant ACCOUNT_STORAGE_SLOT = keccak256("diamond.standard.storage.account");

	struct Layout {
		// Users deposited amounts
		mapping(address => uint256) balances;
		mapping(address => utUint256) allocatedBalances;
		mapping(address => ctUint256) observerAllocatedBalances;
		// position value will become pending locked before openPosition and will be locked after that
		mapping(address => LockedValues) pendingLockedBalances;
		mapping(address => UserLockedValues) observerPendingLockedBalances;
		mapping(address => LockedValues) lockedBalances;
		mapping(address => UserLockedValues) observerLockedBalances;
		mapping(address => mapping(address => utUint256)) partyBAllocatedBalances;
		mapping(address => mapping(address => ctUint256)) observerPartyBAllocatedBalances;
		mapping(address => mapping(address => LockedValues)) partyBPendingLockedBalances;
		mapping(address => mapping(address => UserLockedValues)) observerPartyBPendingLockedBalances;
		mapping(address => mapping(address => LockedValues)) partyBLockedBalances;
		mapping(address => mapping(address => UserLockedValues)) observerPartyBLockedBalances;
		mapping(address => uint256) withdrawCooldown; // is better to call lastDeallocateTime
		mapping(address => uint256) partyANonces;
		mapping(address => mapping(address => uint256)) partyBNonces;
		mapping(address => bool) suspendedAddresses;
		mapping(address => LiquidationDetail) liquidationDetails;
		mapping(address => mapping(uint256 => Price)) symbolsPrices;
		mapping(address => address[]) liquidators;
		mapping(address => uint256) partyAReimbursement;
		mapping(address => utUint256) encryptedPartyAReimbursement;
		mapping(address => ctUint256) observerEncryptedPartyAReimbursement;
		mapping(address => utUint256) encryptedFeeCollectorBalances;
		mapping(address => ctUint256) observerEncryptedFeeCollectorBalances;
		// partyA => partyB => SettlementState
		mapping(address => mapping(address => SettlementState)) settlementStates;
		mapping(address => mapping(address => ObserverSettlementState)) observerSettlementStates;
		mapping(address => mapping(address => ObserverSettlementState)) partyBSettlementStates;
		mapping(address => uint256) reserveVault;
		mapping(address => utUint256) encryptedReserveVault;
		mapping(address => ctUint256) observerEncryptedReserveVault;
		// User encryption address management
		mapping(address => address) userEncryptionAddress;
		address trustedObserverAddress;
		mapping(address => address[]) partyBConnectedPartyAs;
		mapping(address => mapping(address => bool)) partyBConnectedPartyA;
		mapping(address => utUint256) encryptedLiquidationDeficit;
		mapping(address => ctUint256) observerEncryptedLiquidationDeficit;
		mapping(address => utUint256) encryptedLiquidationFee;
		mapping(address => ctUint256) observerEncryptedLiquidationFee;
		/// @dev Binds symbolsPrices[partyA][symbolId] to the liquidationId that wrote them (M-02).
		mapping(address => mapping(uint256 => bytes32)) symbolPriceLiquidationId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = ACCOUNT_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
