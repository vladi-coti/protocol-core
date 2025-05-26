// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../utils/mpc/MpcCore.sol";

library PrivateQuoteStorage {
	bytes32 internal constant PRIVATE_QUOTE_STORAGE_SLOT = keccak256("diamond.standard.storage.privatequote");

	struct Layout {
		// Mapping from quoteId to encrypted quantity
		mapping(uint256 => utUint64) privateQuantities;
		// Mapping from quoteId to encrypted closedAmount
		mapping(uint256 => utUint64) privateClosedAmounts;
		// Mapping from quoteId to encrypted partyA address
		mapping(uint256 => utUint64) privatePartyA;
		// Mapping from quoteId to encrypted partyB address
		mapping(uint256 => utUint64) privatePartyB;
		// Mapping to track which quotes have private mode enabled
		mapping(uint256 => bool) isPrivateEnabled;
		// Mapping from user address to their encryption preferences
		mapping(address => address) userEncryptionAddress;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = PRIVATE_QUOTE_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
