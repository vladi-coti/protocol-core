// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../storages/AccountStorage.sol";
import { EncryptedLockedValues } from "../storages/PrivateQuoteStorage.sol";
import { LockedValues } from "../storages/QuoteStorage.sol";

/**
 * @title LibPrivateLockedValues
 * @notice Library for handling encrypted locked values using MPC arithmetic
 * @dev All operations maintain privacy by working with encrypted values
 */

library PrivateLockedValuesOps {
	using MpcCore for gtUint256;
	using MpcCore for gtBool;

	/**
	 * @notice Adds the values of two EncryptedLockedValues structs.
	 * @param self The EncryptedLockedValues struct to which values will be added.
	 * @param a The EncryptedLockedValues struct containing values to be added.
	 * @return The updated EncryptedLockedValues struct.
	 */
	function add(EncryptedLockedValues memory self, EncryptedLockedValues memory a) internal returns (EncryptedLockedValues memory) {
		return
			EncryptedLockedValues({
				cva: self.cva.add(a.cva),
				partyAmm: self.partyAmm.add(a.partyAmm),
				partyBmm: self.partyBmm.add(a.partyBmm),
				lf: self.lf.add(a.lf)
			});
	}

	/**
	 * @notice Subtracts the values of two EncryptedLockedValues structs.
	 * @param self The EncryptedLockedValues struct from which values will be subtracted.
	 * @param a The EncryptedLockedValues struct containing values to be subtracted.
	 * @return The updated EncryptedLockedValues struct.
	 */
	function sub(EncryptedLockedValues memory self, EncryptedLockedValues memory a) internal returns (EncryptedLockedValues memory) {
		return
			EncryptedLockedValues({
				cva: self.cva.sub(a.cva),
				partyAmm: self.partyAmm.sub(a.partyAmm),
				partyBmm: self.partyBmm.sub(a.partyBmm),
				lf: self.lf.sub(a.lf)
			});
	}

	/**
	 * @notice Creates a zero EncryptedLockedValues struct.
	 * @return A zero EncryptedLockedValues struct.
	 */
	function makeZero() internal returns (EncryptedLockedValues memory) {
		gtUint256 memory zero = MpcCore.setPublic256(0);
		return EncryptedLockedValues({ cva: zero, partyAmm: zero, partyBmm: zero, lf: zero });
	}

	/**
	 * @notice Calculates the total encrypted locked balance for Party A.
	 * @param self The EncryptedLockedValues struct containing locked values.
	 * @return The total encrypted locked balance for Party A.
	 */
	function totalForPartyA(EncryptedLockedValues memory self) internal returns (gtUint256 memory) {
		return self.cva.add(self.partyAmm).add(self.lf);
	}

	/**
	 * @notice Calculates the total encrypted locked balance for Party B.
	 * @param self The EncryptedLockedValues struct containing locked values.
	 * @return The total encrypted locked balance for Party B.
	 */
	function totalForPartyB(EncryptedLockedValues memory self) internal returns (gtUint256 memory) {
		return self.cva.add(self.partyBmm).add(self.lf);
	}

	/**
	 * @notice Multiplies all values of an EncryptedLockedValues struct by an encrypted scalar.
	 * @param self The EncryptedLockedValues struct to be multiplied.
	 * @param a The encrypted scalar value to multiply by.
	 * @return The updated EncryptedLockedValues struct.
	 */
	function mul(EncryptedLockedValues memory self, gtUint256 memory a) internal returns (EncryptedLockedValues memory) {
		return EncryptedLockedValues({ cva: self.cva.mul(a), partyAmm: self.partyAmm.mul(a), partyBmm: self.partyBmm.mul(a), lf: self.lf.mul(a) });
	}

	/**
	 * @notice Multiplies all values of an EncryptedLockedValues struct by a public scalar.
	 * @param self The EncryptedLockedValues struct to be multiplied.
	 * @param a The public scalar value to multiply by.
	 * @return The updated EncryptedLockedValues struct.
	 */
	function mulPublic(EncryptedLockedValues memory self, uint256 a) internal returns (EncryptedLockedValues memory) {
		gtUint256 memory encryptedScalar = MpcCore.setPublic256(a);
		return mul(self, encryptedScalar);
	}

	/**
	 * @notice Divides all values of an EncryptedLockedValues struct by an encrypted scalar.
	 * @param self The EncryptedLockedValues struct to be divided.
	 * @param a The encrypted scalar value to divide by.
	 * @return The updated EncryptedLockedValues struct.
	 */
	function div(EncryptedLockedValues memory self, gtUint256 memory a) internal returns (EncryptedLockedValues memory) {
		self.cva = self.cva.div(a);
		self.partyAmm = self.partyAmm.div(a);
		self.partyBmm = self.partyBmm.div(a);
		self.lf = self.lf.div(a);
		return self;
	}

	/**
	 * @notice Divides all values of an EncryptedLockedValues struct by a public scalar.
	 * @param self The EncryptedLockedValues struct to be divided.
	 * @param a The public scalar value to divide by.
	 * @return The updated EncryptedLockedValues struct.
	 */
	function divPublic(EncryptedLockedValues memory self, uint256 a) internal returns (EncryptedLockedValues memory) {
		gtUint256 memory encryptedScalar = MpcCore.setPublic256(a);
		return div(self, encryptedScalar);
	}

	/**
	 * @notice Converts plaintext LockedValues to EncryptedLockedValues.
	 * @param lockedValues The plaintext LockedValues struct.
	 * @return The equivalent EncryptedLockedValues struct.
	 */
	function fromPlaintext(LockedValues memory lockedValues) internal returns (EncryptedLockedValues memory) {
		return
			EncryptedLockedValues({
				cva: MpcCore.setPublic256(lockedValues.cva),
				partyAmm: MpcCore.setPublic256(lockedValues.partyAmm),
				partyBmm: MpcCore.setPublic256(lockedValues.partyBmm),
				lf: MpcCore.setPublic256(lockedValues.lf)
			});
	}

	/**
	 * @notice Converts EncryptedLockedValues to plaintext LockedValues.
	 * @dev WARNING: This function breaks privacy by decrypting values.
	 * Only use for final outputs or authorized reveals.
	 * @param encryptedValues The EncryptedLockedValues struct.
	 * @return The decrypted plaintext LockedValues struct.
	 */
	function toPlaintext(EncryptedLockedValues memory encryptedValues) internal returns (LockedValues memory) {
		return
			LockedValues({
				cva: MpcCore.decrypt(encryptedValues.cva),
				partyAmm: MpcCore.decrypt(encryptedValues.partyAmm),
				partyBmm: MpcCore.decrypt(encryptedValues.partyBmm),
				lf: MpcCore.decrypt(encryptedValues.lf)
			});
	}

	/**
	 * @notice Checks if two EncryptedLockedValues structs are equal.
	 * @param self The first EncryptedLockedValues struct.
	 * @param other The second EncryptedLockedValues struct.
	 * @return An encrypted boolean indicating equality.
	 */
	function eq(EncryptedLockedValues memory self, EncryptedLockedValues memory other) internal returns (gtBool) {
		gtBool cvaEq = self.cva.eq(other.cva);
		gtBool partyAmmEq = self.partyAmm.eq(other.partyAmm);
		gtBool partyBmmEq = self.partyBmm.eq(other.partyBmm);
		gtBool lfEq = self.lf.eq(other.lf);

		return cvaEq.and(partyAmmEq).and(partyBmmEq).and(lfEq);
	}

	/**
	 * @notice Performs conditional selection between two EncryptedLockedValues structs.
	 * @param condition The encrypted boolean condition.
	 * @param trueValue The EncryptedLockedValues to select if condition is true.
	 * @param falseValue The EncryptedLockedValues to select if condition is false.
	 * @return The conditionally selected EncryptedLockedValues struct.
	 */
	function mux(
		gtBool condition,
		EncryptedLockedValues memory trueValue,
		EncryptedLockedValues memory falseValue
	) internal returns (EncryptedLockedValues memory) {
		return
			EncryptedLockedValues({
				cva: condition.mux(trueValue.cva, falseValue.cva),
				partyAmm: condition.mux(trueValue.partyAmm, falseValue.partyAmm),
				partyBmm: condition.mux(trueValue.partyBmm, falseValue.partyBmm),
				lf: condition.mux(trueValue.lf, falseValue.lf)
			});
	}

	// ======================
	// ENCRYPTED STORAGE MANAGEMENT FUNCTIONS
	// ======================

	/**
	 * @notice Adds encrypted locked values to a user's pending locked balances
	 * @param user The user address
	 * @param values The encrypted locked values to add
	 */
	function addToPendingLocked(address user, EncryptedLockedValues memory values) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		accountLayout.useEncryptedBalances[user] = true;
		accountLayout.encryptedPendingLockedBalances[user] = add(accountLayout.encryptedPendingLockedBalances[user], values);
	}

	/**
	 * @notice Subtracts encrypted locked values from a user's pending locked balances
	 * @param user The user address
	 * @param values The encrypted locked values to subtract
	 */
	function subFromPendingLocked(address user, EncryptedLockedValues memory values) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		if (accountLayout.useEncryptedBalances[user]) {
			accountLayout.encryptedPendingLockedBalances[user] = sub(accountLayout.encryptedPendingLockedBalances[user], values);
		}
	}

	/**
	 * @notice Moves encrypted values from pending to locked balances
	 * @param user The user address
	 */
	function lockPendingBalances(address user) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		if (accountLayout.useEncryptedBalances[user]) {
			accountLayout.encryptedLockedBalances[user] = add(
				accountLayout.encryptedLockedBalances[user],
				accountLayout.encryptedPendingLockedBalances[user]
			);
			accountLayout.encryptedPendingLockedBalances[user] = makeZero();
		}
	}

	/**
	 * @notice Gets encrypted pending locked balances for a user
	 * @param user The user address
	 * @return The encrypted pending locked balances
	 */
	function getPendingLocked(address user) internal returns (EncryptedLockedValues memory) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		if (accountLayout.useEncryptedBalances[user]) {
			return accountLayout.encryptedPendingLockedBalances[user];
		}
		// Return zero if not using encrypted balances
		return makeZero();
	}

	/**
	 * @notice Gets encrypted locked balances for a user
	 * @param user The user address
	 * @return The encrypted locked balances
	 */
	function getLocked(address user) internal returns (EncryptedLockedValues memory) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		if (accountLayout.useEncryptedBalances[user]) {
			return accountLayout.encryptedLockedBalances[user];
		}
		// Return zero if not using encrypted balances
		return makeZero();
	}

	/**
	 * @notice Checks if a user is using encrypted balances
	 * @param user The user address
	 * @return True if user is using encrypted balances
	 */
	function isUsingEncryptedBalances(address user) internal returns (bool) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		return accountLayout.useEncryptedBalances[user];
	}

	/**
	 * @notice Migrates plaintext locked values to encrypted for a user
	 * @param user The user address
	 */
	function migrateToEncrypted(address user) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// Convert existing plaintext balances to encrypted
		if (!accountLayout.useEncryptedBalances[user]) {
			accountLayout.encryptedPendingLockedBalances[user] = fromPlaintext(accountLayout.pendingLockedBalances[user]);
			accountLayout.encryptedLockedBalances[user] = fromPlaintext(accountLayout.lockedBalances[user]);
			accountLayout.useEncryptedBalances[user] = true;

			// Clear plaintext balances for privacy
			accountLayout.pendingLockedBalances[user] = LockedValues(0, 0, 0, 0);
			accountLayout.lockedBalances[user] = LockedValues(0, 0, 0, 0);
		}
	}
}
