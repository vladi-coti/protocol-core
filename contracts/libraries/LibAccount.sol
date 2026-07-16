// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./LibLockedValues.sol";
import "./LibEncryption.sol";
import "../storages/AccountStorage.sol";

library LibAccount {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	/**
	 * @notice Returns the encryption address for a user.
	 * @param user The address of the user.
	 * @return The encryption address for the user.
	 */
	function getUserEncryptionAddress(address user) internal view returns (address) {
		return LibEncryption.getUserEncryptionAddress(user);
	}

	/**
	 * @notice Calculates the total locked balances of Party A.
	 * @param partyA The address of Party A.
	 * @return The total locked balances of Party A (encrypted).
	 */
	function partyATotalLockedBalances(address partyA) internal returns (gtUint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.pendingLockedBalances[partyA].onBoard();
		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();

		return garbledPendingLockedBalances.totalForPartyA().checkedAdd(garbledLockedBalances.totalForPartyA());
	}

	/**
	 * @notice Calculates the total locked balances of Party B for a specific Party A.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The total locked balances of Party B for the specified Party A (encrypted).
	 */
	function partyBTotalLockedBalances(address partyB, address partyA) internal returns (gtUint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.partyBPendingLockedBalances[partyB][partyA].onBoard();
		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		return garbledPendingLockedBalances.totalForPartyB().checkedAdd(garbledLockedBalances.totalForPartyB());
	}

	/**
	 * @notice Calculates the available balance for a quote for Party A.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyA The address of Party A.
	 * @return The available balance for a quote for Party A (encrypted).
	 */
	function partyAAvailableForQuote(int256 upnl, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = LibEncryption.toNonNegativeSigned(LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);

		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();
		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.pendingLockedBalances[partyA].onBoard();

		gtInt256 totalLocked = LibEncryption.toNonNegativeSigned(garbledLockedBalances.totalForPartyA().checkedAdd(garbledPendingLockedBalances.totalForPartyA()));

		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.checkedAdd(gtUpnl).checkedSub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyAmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = LibEncryption.toNonNegativeSigned(garbledLockedBalances.partyAmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, mm, negUpnl);

			gtInt256 cvaLfPendingTotal = LibEncryption.toNonNegativeSigned(
				garbledLockedBalances.cva.checkedAdd(garbledLockedBalances.lf).checkedAdd(garbledPendingLockedBalances.totalForPartyA())
			);
			return allocatedBalance.checkedSub(cvaLfPendingTotal).checkedSub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for Party A.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyA The address of Party A.
	 * @return The available balance for Party A (encrypted).
	 */
	function partyAAvailableBalance(int256 upnl, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = LibEncryption.toNonNegativeSigned(LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);

		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();
		gtInt256 totalLocked = LibEncryption.toNonNegativeSigned(garbledLockedBalances.totalForPartyA());

		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.checkedAdd(gtUpnl).checkedSub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyAmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = LibEncryption.toNonNegativeSigned(garbledLockedBalances.partyAmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, mm, negUpnl);

			gtInt256 cvaLf = LibEncryption.toNonNegativeSigned(garbledLockedBalances.cva.checkedAdd(garbledLockedBalances.lf));
			return allocatedBalance.checkedSub(cvaLf).checkedSub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party A.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party A (encrypted).
	 */
	function partyAAvailableBalanceForLiquidation(int256 upnl, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = LibEncryption.toNonNegativeSigned(LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext));
		return _partyAAvailableBalanceForLiquidation(upnl, allocatedBalance, partyA);
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party A using an explicit allocated balance snapshot.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param allocatedBalance The allocated balance snapshot to use.
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party A (encrypted).
	 */
	function partyAAvailableBalanceForLiquidation(int256 upnl, uint256 allocatedBalance, address partyA) internal returns (gtInt256) {
		gtInt256 gtAllocatedBalance = LibEncryption.toNonNegativeSigned(MpcCore.setPublic256(allocatedBalance));
		return _partyAAvailableBalanceForLiquidation(upnl, gtAllocatedBalance, partyA);
	}

	function _partyAAvailableBalanceForLiquidation(
		int256 upnl,
		gtInt256 allocatedBalance,
		address partyA
	) private returns (gtInt256) {
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);

		GarbledLockedValues memory garbledLockedBalances = AccountStorage.layout().lockedBalances[partyA].onBoard();
		gtInt256 cvaLf = LibEncryption.toNonNegativeSigned(garbledLockedBalances.cva.checkedAdd(garbledLockedBalances.lf));

		gtInt256 freeBalance = allocatedBalance.checkedSub(cvaLf);
		return freeBalance.checkedAdd(gtUpnl);
	}

	/**
	 * @notice Calculates the available balance for a quote for Party B.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for a quote for Party B (encrypted).
	 */
	function partyBAvailableForQuote(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = LibEncryption.toNonNegativeSigned(LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);

		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.partyBPendingLockedBalances[partyB][partyA].onBoard();

		gtInt256 totalLocked = LibEncryption.toNonNegativeSigned(garbledLockedBalances.totalForPartyB().checkedAdd(garbledPendingLockedBalances.totalForPartyB()));

		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.checkedAdd(gtUpnl).checkedSub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyBmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = LibEncryption.toNonNegativeSigned(garbledLockedBalances.partyBmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, mm, negUpnl);

			gtInt256 cvaLfPendingTotal = LibEncryption.toNonNegativeSigned(
				garbledLockedBalances.cva.checkedAdd(garbledLockedBalances.lf).checkedAdd(garbledPendingLockedBalances.totalForPartyB())
			);
			return allocatedBalance.checkedSub(cvaLfPendingTotal).checkedSub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for Party B.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for Party B (encrypted).
	 */
	function partyBAvailableBalance(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = LibEncryption.toNonNegativeSigned(LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);

		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		gtInt256 totalLocked = LibEncryption.toNonNegativeSigned(garbledLockedBalances.totalForPartyB());

		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.checkedAdd(gtUpnl).checkedSub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyBmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = LibEncryption.toNonNegativeSigned(garbledLockedBalances.partyBmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, mm, negUpnl);

			gtInt256 cvaLf = LibEncryption.toNonNegativeSigned(garbledLockedBalances.cva.checkedAdd(garbledLockedBalances.lf));
			return allocatedBalance.checkedSub(cvaLf).checkedSub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party B.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party B (encrypted).
	 */
	function partyBAvailableBalanceForLiquidation(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalanceEncrypted = LibEncryption.toNonNegativeSigned(
			LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext)
		);
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);

		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		gtInt256 cvaLf = LibEncryption.toNonNegativeSigned(garbledLockedBalances.cva.checkedAdd(garbledLockedBalances.lf));

		gtInt256 freeBalance = allocatedBalanceEncrypted.checkedSub(cvaLf);
		return freeBalance.checkedAdd(gtUpnl);
	}

	/**
	 * @notice Checks whether an encrypted signed balance is non-negative.
	 * @param gtAvailableBalance The encrypted signed balance.
	 * @return Whether the balance is greater than or equal to zero.
	 */
	function isNonNegative(gtInt256 gtAvailableBalance) internal returns (gtBool) {
		return gtAvailableBalance.ge(MpcCore.setPublic256(int256(0)));
	}

	/**
	 * @notice Checks whether an encrypted signed balance covers an encrypted unsigned amount.
	 * @dev Callers should separately guard non-negativity when they need a distinct revert reason.
	 *      Reinterpreting a non-negative signed value as unsigned preserves the magnitude.
	 * @param gtAvailableBalance The encrypted signed balance.
	 * @param gtAmount The encrypted unsigned amount to compare against.
	 * @return Whether the balance is greater than or equal to the amount.
	 */
	function isAtLeastAmount(gtInt256 gtAvailableBalance, gtUint256 gtAmount) internal returns (gtBool) {
		return MpcCore.fromSigned(gtAvailableBalance).ge(gtAmount);
	}

	/**
	 * @notice Initializes Party A encrypted values to encrypted zeros if uninitialized.
	 * @dev This function checks and initializes Party A encrypted storage in a single call.
	 * @param partyA The address of Party A whose encrypted values should be initialized.
	 */
	function initializePartyA(address partyA) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address encryptionAddress = getUserEncryptionAddress(partyA);

		// Initialize Party A locked balances if uninitialized
		LockedValues storage lockedBalances = accountLayout.lockedBalances[partyA];
		LockedValues storage pendingLockedBalances = accountLayout.pendingLockedBalances[partyA];

		if (lockedBalances.isUninitialized()) {
			lockedBalances.initializeToZeros(encryptionAddress);
			accountLayout.observerLockedBalances[partyA] = _observerLockedZeros();
		}
		if (pendingLockedBalances.isUninitialized()) {
			pendingLockedBalances.initializeToZeros(encryptionAddress);
			accountLayout.observerPendingLockedBalances[partyA] = _observerLockedZeros();
		}

		// Initialize Party A allocated balance if uninitialized (contains zeros)
		if (
			ctUint128.unwrap(accountLayout.allocatedBalances[partyA].ciphertext.ciphertextHigh) == 0 &&
			ctUint128.unwrap(accountLayout.allocatedBalances[partyA].ciphertext.ciphertextLow) == 0
		) {
			gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
			accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtZero, encryptionAddress);
			accountLayout.observerAllocatedBalances[partyA] = LibEncryption.offBoardToObserver(gtZero);
		}
	}

	/**
	 * @notice Initializes Party B encrypted values for a specific Party A to encrypted zeros if uninitialized.
	 * @dev This function checks and initializes Party B encrypted storage in a single call.
	 * @param partyB The address of Party B whose encrypted values should be initialized.
	 * @param partyA The address of Party A for which to initialize values.
	 */
	function initializePartyB(address partyB, address partyA) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address encryptionAddress = getUserEncryptionAddress(partyB);

		if (!accountLayout.partyBConnectedPartyA[partyB][partyA]) {
			accountLayout.partyBConnectedPartyA[partyB][partyA] = true;
			accountLayout.partyBConnectedPartyAs[partyB].push(partyA);
		}

		LockedValues storage lockedBalances = accountLayout.partyBLockedBalances[partyB][partyA];
		LockedValues storage pendingLockedBalances = accountLayout.partyBPendingLockedBalances[partyB][partyA];
		SettlementState storage settlementState = accountLayout.settlementStates[partyA][partyB];

		if (lockedBalances.isUninitialized()) {
			lockedBalances.initializeToZeros(encryptionAddress);
			accountLayout.observerPartyBLockedBalances[partyB][partyA] = _observerLockedZeros();
		}
		if (pendingLockedBalances.isUninitialized()) {
			pendingLockedBalances.initializeToZeros(encryptionAddress);
			accountLayout.observerPartyBPendingLockedBalances[partyB][partyA] = _observerLockedZeros();
		}
		if (_isSettlementStateUninitialized(settlementState)) {
			initializeToZeros(settlementState, getUserEncryptionAddress(partyA));
			initializeObserverToZeros(accountLayout.observerSettlementStates[partyA][partyB]);
			initializeUserToZeros(accountLayout.partyBSettlementStates[partyA][partyB], encryptionAddress);
		} else if (_isObserverSettlementStateUninitialized(accountLayout.partyBSettlementStates[partyA][partyB])) {
			initializeUserToZeros(accountLayout.partyBSettlementStates[partyA][partyB], encryptionAddress);
		}

		// Initialize Party B allocated balance for this Party A if uninitialized (contains zeros)
		if (
			ctUint128.unwrap(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext.ciphertextHigh) == 0 &&
			ctUint128.unwrap(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext.ciphertextLow) == 0
		) {
			gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
			accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtZero, encryptionAddress);
			accountLayout.observerPartyBAllocatedBalances[partyB][partyA] = LibEncryption.offBoardToObserver(gtZero);
		}
	}

	/**
	 * @notice Initializes or migrates Party B reserve vault storage into encrypted form.
	 * @param partyB The address of Party B.
	 * @return gtReserveBalance The encrypted reserve vault balance.
	 */
	function initializeReserveVault(address partyB) internal returns (gtUint256 gtReserveBalance) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address encryptionAddress = getUserEncryptionAddress(partyB);
		utUint256 storage encryptedReserveVault = accountLayout.encryptedReserveVault[partyB];
		uint256 legacyReserveVault = accountLayout.reserveVault[partyB];

		if (legacyReserveVault > 0) {
			gtReserveBalance = MpcCore.setPublic256(legacyReserveVault);
			encryptedReserveVault.ciphertext = MpcCore.offBoard(gtReserveBalance);
			encryptedReserveVault.userCiphertext = MpcCore.offBoardToUser(gtReserveBalance, encryptionAddress);
			accountLayout.observerEncryptedReserveVault[partyB] = LibEncryption.offBoardToObserver(gtReserveBalance);
			accountLayout.reserveVault[partyB] = 0;
			return gtReserveBalance;
		}

		if (
			ctUint128.unwrap(encryptedReserveVault.ciphertext.ciphertextHigh) == 0 &&
			ctUint128.unwrap(encryptedReserveVault.ciphertext.ciphertextLow) == 0
		) {
			// Leave storage empty; callers persist via store. Avoids OffBoardToUser to
			// un-onboarded contract addresses during setEncryptionAddress bootstrap.
			return MpcCore.setPublic256(uint256(0));
		}

		return LockedValuesOps.safeOnboard(encryptedReserveVault.ciphertext);
	}

	/**
	 * @notice Initializes Party A reimbursement storage into encrypted form if needed.
	 * @param partyA The address of Party A.
	 * @return gtReimbursement The encrypted reimbursement balance.
	 */
	function initializePartyAReimbursement(address partyA) internal returns (gtUint256 gtReimbursement) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address encryptionAddress = getUserEncryptionAddress(partyA);
		utUint256 storage encryptedReimbursement = accountLayout.encryptedPartyAReimbursement[partyA];
		uint256 legacyReimbursement = accountLayout.partyAReimbursement[partyA];

		if (legacyReimbursement > 0) {
			gtReimbursement = MpcCore.setPublic256(legacyReimbursement);
			accountLayout.encryptedPartyAReimbursement[partyA] = MpcCore.offBoardCombined(gtReimbursement, encryptionAddress);
			accountLayout.observerEncryptedPartyAReimbursement[partyA] = LibEncryption.offBoardToObserver(gtReimbursement);
			accountLayout.partyAReimbursement[partyA] = 0;
			return gtReimbursement;
		}

		if (
			ctUint128.unwrap(encryptedReimbursement.ciphertext.ciphertextHigh) == 0 &&
			ctUint128.unwrap(encryptedReimbursement.ciphertext.ciphertextLow) == 0
		) {
			return MpcCore.setPublic256(uint256(0));
		}

		return LockedValuesOps.safeOnboard(encryptedReimbursement.ciphertext);
	}

	/**
	 * @notice Initializes fee collector accrual storage into encrypted form if needed.
	 * @param feeCollector The address receiving protocol fees.
	 * @return gtFeeBalance The encrypted fee collector balance.
	 */
	function initializeFeeCollectorBalance(address feeCollector) internal returns (gtUint256 gtFeeBalance) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		utUint256 storage encryptedFeeBalance = accountLayout.encryptedFeeCollectorBalances[feeCollector];

		if (
			ctUint128.unwrap(encryptedFeeBalance.ciphertext.ciphertextHigh) == 0 &&
			ctUint128.unwrap(encryptedFeeBalance.ciphertext.ciphertextLow) == 0
		) {
			return MpcCore.setPublic256(uint256(0));
		}

		return LockedValuesOps.safeOnboard(encryptedFeeBalance.ciphertext);
	}

	/**
	 * @notice Initializes SettlementState storage to encrypted zeros for a user.
	 * @param self The SettlementState storage struct to initialize.
	 * @param encryptionAddress The encryption address of the party.
	 */
	function initializeToZeros(SettlementState storage self, address encryptionAddress) internal {
		gtInt256 gtZeroInt = MpcCore.setPublic256(int256(0));
		gtUint256 gtZeroUint = MpcCore.setPublic256(uint256(0));
		self.actualAmount = MpcCore.offBoardCombined(gtZeroInt, encryptionAddress);
		self.expectedAmount = MpcCore.offBoardCombined(gtZeroInt, encryptionAddress);
		self.cva = MpcCore.offBoardCombined(gtZeroUint, encryptionAddress);
		self.pending = false;
	}

	function initializeObserverToZeros(ObserverSettlementState storage self) internal {
		gtInt256 gtZeroInt = MpcCore.setPublic256(int256(0));
		gtUint256 gtZeroUint = MpcCore.setPublic256(uint256(0));
		self.actualAmount = LibEncryption.offBoardToObserver(gtZeroInt);
		self.expectedAmount = LibEncryption.offBoardToObserver(gtZeroInt);
		self.cva = LibEncryption.offBoardToObserver(gtZeroUint);
	}

	function initializeUserToZeros(ObserverSettlementState storage self, address encryptionAddress) internal {
		gtInt256 gtZeroInt = MpcCore.setPublic256(int256(0));
		gtUint256 gtZeroUint = MpcCore.setPublic256(uint256(0));
		self.actualAmount = MpcCore.offBoardToUser(gtZeroInt, encryptionAddress);
		self.expectedAmount = MpcCore.offBoardToUser(gtZeroInt, encryptionAddress);
		self.cva = MpcCore.offBoardToUser(gtZeroUint, encryptionAddress);
	}

	function _isSettlementStateUninitialized(SettlementState storage self) private view returns (bool) {
		return (
			ctInt128.unwrap(self.actualAmount.ciphertext.ciphertextHigh) == 0 &&
			ctInt128.unwrap(self.actualAmount.ciphertext.ciphertextLow) == 0 &&
			ctInt128.unwrap(self.expectedAmount.ciphertext.ciphertextHigh) == 0 &&
			ctInt128.unwrap(self.expectedAmount.ciphertext.ciphertextLow) == 0 &&
			ctUint128.unwrap(self.cva.ciphertext.ciphertextHigh) == 0 &&
			ctUint128.unwrap(self.cva.ciphertext.ciphertextLow) == 0
		);
	}

	function _isObserverSettlementStateUninitialized(ObserverSettlementState storage self) private view returns (bool) {
		return (
			ctInt128.unwrap(self.actualAmount.ciphertextHigh) == 0 &&
			ctInt128.unwrap(self.actualAmount.ciphertextLow) == 0 &&
			ctInt128.unwrap(self.expectedAmount.ciphertextHigh) == 0 &&
			ctInt128.unwrap(self.expectedAmount.ciphertextLow) == 0 &&
			ctUint128.unwrap(self.cva.ciphertextHigh) == 0 &&
			ctUint128.unwrap(self.cva.ciphertextLow) == 0
		);
	}

	function _observerLockedZeros() private returns (UserLockedValues memory) {
		gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
		address observer = LibEncryption.getObserverEncryptionAddress();
		if (observer == address(0)) {
			return UserLockedValues({
				cva: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) }),
				lf: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) }),
				partyAmm: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) }),
				partyBmm: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) })
			});
		}
		return LockedValuesOps.offBoardToUser(
			GarbledLockedValues({ cva: gtZero, lf: gtZero, partyAmm: gtZero, partyBmm: gtZero }),
			observer
		);
	}
}
