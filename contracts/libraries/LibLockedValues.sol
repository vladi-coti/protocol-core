// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/QuoteStorage.sol";

/**
 * @title LibLockedValues
 * @notice Library for handling encrypted locked values using MPC arithmetic
 * @dev All operations maintain privacy by working with encrypted values
 */

library LockedValuesOps {
	using MpcCore for gtUint256;
	using MpcCore for gtBool;

	function safeOnboard(ctUint256 memory value) internal returns (gtUint256) {
		if (ctUint128.unwrap(value.ciphertextHigh) == uint256(0) && ctUint128.unwrap(value.ciphertextLow) == uint256(0)) {
			return MpcCore.setPublic256(uint256(0));
		}
		return MpcCore.onBoard(value);
	}

	/**
	 * @notice Converts a LockedValues struct to a GarbledLockedValues struct.
	 * @param self The LockedValues struct to be converted.
	 * @return The converted GarbledLockedValues struct.
	 */
	function onBoard(LockedValues memory self) internal returns (GarbledLockedValues memory) {
		return
			GarbledLockedValues({
				cva: safeOnboard(self.cva.ciphertext),
				partyAmm: safeOnboard(self.partyAmm.ciphertext),
				partyBmm: safeOnboard(self.partyBmm.ciphertext),
				lf: safeOnboard(self.lf.ciphertext)
			});
	}

	/**
	 * @notice Converts a GarbledLockedValues struct to a LockedValues struct.
	 * @param self The GarbledLockedValues struct to be converted.
	 * @param encryptionAddress The encryption address of the party.
	 * @return The converted LockedValues struct.
	 */
	function offBoard(GarbledLockedValues memory self, address encryptionAddress) internal returns (LockedValues memory) {
		return
			LockedValues({
				cva: MpcCore.offBoardCombined(self.cva, encryptionAddress),
				partyAmm: MpcCore.offBoardCombined(self.partyAmm, encryptionAddress),
				partyBmm: MpcCore.offBoardCombined(self.partyBmm, encryptionAddress),
				lf: MpcCore.offBoardCombined(self.lf, encryptionAddress)
			});
	}

	/**
	 * @notice Adds the values of two GarbledLockedValues structs.
	 * @param self The GarbledLockedValues struct to which values will be added.
	 * @param a The GarbledLockedValues struct containing values to be added.
	 * @return The updated GarbledLockedValues struct.
	 */
	function add(GarbledLockedValues memory self, GarbledLockedValues memory a) internal returns (GarbledLockedValues memory) {
		return
			GarbledLockedValues({
				cva: self.cva.add(a.cva),
				partyAmm: self.partyAmm.add(a.partyAmm),
				partyBmm: self.partyBmm.add(a.partyBmm),
				lf: self.lf.add(a.lf)
			});
	}

	/**
	 * @notice Subtracts the values of two GarbledLockedValues structs.
	 * @param self The GarbledLockedValues struct from which values will be subtracted.
	 * @param a The GarbledLockedValues struct containing values to be subtracted.
	 * @return The updated GarbledLockedValues struct.
	 */
	function sub(GarbledLockedValues memory self, GarbledLockedValues memory a) internal returns (GarbledLockedValues memory) {
		return
			GarbledLockedValues({
				cva: self.cva.sub(a.cva),
				partyAmm: self.partyAmm.sub(a.partyAmm),
				partyBmm: self.partyBmm.sub(a.partyBmm),
				lf: self.lf.sub(a.lf)
			});
	}

	/**
	 * @notice Creates a zero GarbledLockedValues struct.
	 * @return A zero GarbledLockedValues struct.
	 */
	function makeZero() internal returns (GarbledLockedValues memory) {
		gtUint256 zero = MpcCore.setPublic256(uint256(0));
		return GarbledLockedValues({ cva: zero, partyAmm: zero, partyBmm: zero, lf: zero });
	}

	/**
	 * @notice Calculates the total encrypted locked balance for Party A.
	 * @param self The GarbledLockedValues struct containing locked values.
	 * @return The total encrypted locked balance for Party A.
	 */
	function totalForPartyA(GarbledLockedValues memory self) internal returns (gtUint256) {
		return self.cva.add(self.partyAmm).add(self.lf);
	}

	/**
	 * @notice Calculates the total encrypted locked balance for Party B.
	 * @param self The GarbledLockedValues struct containing locked values.
	 * @return The total encrypted locked balance for Party B.
	 */
	function totalForPartyB(GarbledLockedValues memory self) internal returns (gtUint256) {
		return self.cva.add(self.partyBmm).add(self.lf);
	}

	/**
	 * @notice Multiplies all values of an GarbledLockedValues struct by an encrypted scalar.
	 * @param self The GarbledLockedValues struct to be multiplied.
	 * @param a The encrypted scalar value to multiply by.
	 * @return The updated GarbledLockedValues struct.
	 */
	function mul(GarbledLockedValues memory self, gtUint256 a) internal returns (GarbledLockedValues memory) {
		return
			GarbledLockedValues({ cva: self.cva.mul(a), partyAmm: self.partyAmm.mul(a), partyBmm: self.partyBmm.mul(a), lf: self.lf.mul(a) });
	}

	/**
	 * @notice Multiplies all values of an GarbledLockedValues struct by a public scalar.
	 * @param self The GarbledLockedValues struct to be multiplied.
	 * @param a The public scalar value to multiply by.
	 * @return The updated GarbledLockedValues struct.
	 */
	function mulPublic(GarbledLockedValues memory self, uint256 a) internal returns (GarbledLockedValues memory) {
		gtUint256 encryptedScalar = MpcCore.setPublic256(a);
		return mul(self, encryptedScalar);
	}

	/**
	 * @notice Divides all values of an GarbledLockedValues struct by an encrypted scalar.
	 * @param self The GarbledLockedValues struct to be divided.
	 * @param a The encrypted scalar value to divide by.
	 * @return The updated GarbledLockedValues struct.
	 */
	function div(GarbledLockedValues memory self, gtUint256 a) internal returns (GarbledLockedValues memory) {
		self.cva = self.cva.div(a);
		self.partyAmm = self.partyAmm.div(a);
		self.partyBmm = self.partyBmm.div(a);
		self.lf = self.lf.div(a);
		return self;
	}

	/**
	 * @notice Divides all values of an GarbledLockedValues struct by a public scalar.
	 * @param self The GarbledLockedValues struct to be divided.
	 * @param a The public scalar value to divide by.
	 * @return The updated GarbledLockedValues struct.
	 */
	function divPublic(GarbledLockedValues memory self, uint256 a) internal returns (GarbledLockedValues memory) {
		gtUint256 encryptedScalar = MpcCore.setPublic256(a);
		return div(self, encryptedScalar);
	}

	/**
	 * @notice Checks if two GarbledLockedValues structs are equal.
	 * @param self The first GarbledLockedValues struct.
	 * @param other The second GarbledLockedValues struct.
	 * @return An encrypted boolean indicating equality.
	 */
	function eq(GarbledLockedValues memory self, GarbledLockedValues memory other) internal returns (gtBool) {
		gtBool cvaEq = self.cva.eq(other.cva);
		gtBool partyAmmEq = self.partyAmm.eq(other.partyAmm);
		gtBool partyBmmEq = self.partyBmm.eq(other.partyBmm);
		gtBool lfEq = self.lf.eq(other.lf);

		return cvaEq.and(partyAmmEq).and(partyBmmEq).and(lfEq);
	}

	/**
	 * @notice Performs conditional selection between two GarbledLockedValues structs.
	 * @param condition The encrypted boolean condition.
	 * @param trueValue The GarbledLockedValues to select if condition is true.
	 * @param falseValue The GarbledLockedValues to select if condition is false.
	 * @return The conditionally selected GarbledLockedValues struct.
	 */
	function mux(
		gtBool condition,
		GarbledLockedValues memory trueValue,
		GarbledLockedValues memory falseValue
	) internal returns (GarbledLockedValues memory) {
		return
			GarbledLockedValues({
				cva: MpcCore.mux(condition, trueValue.cva, falseValue.cva),
				partyAmm: MpcCore.mux(condition, trueValue.partyAmm, falseValue.partyAmm),
				partyBmm: MpcCore.mux(condition, trueValue.partyBmm, falseValue.partyBmm),
				lf: MpcCore.mux(condition, trueValue.lf, falseValue.lf)
			});
	}
}
