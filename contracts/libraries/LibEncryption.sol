// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../storages/AccountStorage.sol";

library LibEncryption {
	function getUserEncryptionAddress(address user) internal view returns (address) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address userEncryptionAddress = accountLayout.userEncryptionAddress[user];
		return userEncryptionAddress == address(0) ? user : userEncryptionAddress;
	}

	function getObserverEncryptionAddress() internal view returns (address) {
		return AccountStorage.layout().trustedObserverAddress;
	}

	function offBoardToUser(gtUint256 value, address user) internal returns (utUint256 memory) {
		return MpcCore.offBoardCombined(value, getUserEncryptionAddress(user));
	}

	function offBoardToUser(gtInt256 value, address user) internal returns (utInt256 memory) {
		return MpcCore.offBoardCombined(value, getUserEncryptionAddress(user));
	}

	function offBoardToObserver(gtUint256 value) internal returns (ctUint256 memory) {
		address observer = getObserverEncryptionAddress();
		if (observer == address(0)) {
			return ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) });
		}
		return MpcCore.offBoardToUser(value, observer);
	}

	function offBoardToObserver(gtInt256 value) internal returns (ctInt256 memory) {
		address observer = getObserverEncryptionAddress();
		if (observer == address(0)) {
			return ctInt256({ ciphertextHigh: ctInt128.wrap(0), ciphertextLow: ctInt128.wrap(0) });
		}
		return MpcCore.offBoardToUser(value, observer);
	}

	function offBoardLockedToObserver(GarbledLockedValues memory values) internal returns (UserLockedValues memory) {
		address observer = getObserverEncryptionAddress();
		if (observer == address(0)) {
			return UserLockedValues({
				cva: emptyUint256(),
				lf: emptyUint256(),
				partyAmm: emptyUint256(),
				partyBmm: emptyUint256()
			});
		}
		return UserLockedValues({
			cva: MpcCore.offBoardToUser(values.cva, observer),
			lf: MpcCore.offBoardToUser(values.lf, observer),
			partyAmm: MpcCore.offBoardToUser(values.partyAmm, observer),
			partyBmm: MpcCore.offBoardToUser(values.partyBmm, observer)
		});
	}

	function storePartyAAllocatedBalance(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) internal {
		accountLayout.allocatedBalances[partyA] = offBoardToUser(value, partyA);
		accountLayout.observerAllocatedBalances[partyA] = offBoardToObserver(value);
	}

	function storePartyBAllocatedBalance(AccountStorage.Layout storage accountLayout, address partyB, address partyA, gtUint256 value) internal {
		accountLayout.partyBAllocatedBalances[partyB][partyA] = offBoardToUser(value, partyB);
		accountLayout.observerPartyBAllocatedBalances[partyB][partyA] = offBoardToObserver(value);
	}

	function storeReserveVault(AccountStorage.Layout storage accountLayout, address partyB, gtUint256 value) internal {
		accountLayout.encryptedReserveVault[partyB] = offBoardToUser(value, partyB);
		accountLayout.observerEncryptedReserveVault[partyB] = offBoardToObserver(value);
	}

	function storeFeeCollectorBalance(AccountStorage.Layout storage accountLayout, address feeCollector, gtUint256 value) internal {
		accountLayout.encryptedFeeCollectorBalances[feeCollector] = offBoardToUser(value, feeCollector);
		accountLayout.observerEncryptedFeeCollectorBalances[feeCollector] = offBoardToObserver(value);
	}

	function emptyUint256() internal pure returns (ctUint256 memory) {
		return ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) });
	}
}
