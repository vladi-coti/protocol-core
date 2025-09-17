// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/PrivateQuoteStorage.sol";

/**
 * @title LibLockedPrivateValues
 * @notice Library for handling encrypted locked values using MPC arithmetic
 * @dev All operations maintain privacy by working with encrypted values
 */

library LockedPrivateValuesOps {
	using MpcCore for gtUint256;
	using MpcCore for gtBool;

	/**
	 * @notice Converts a PrivateLockedValues struct to a GarbledPrivateLockedValues struct.
	 * @param self The PrivateLockedValues struct to be converted.
	 * @return The converted GarbledPrivateLockedValues struct.
	 */
	function onBoard(PrivateLockedValues memory self) internal returns (GarbledPrivateLockedValues memory) {
		return
			GarbledPrivateLockedValues({
				cva: MpcCore.onBoard(self.cva.ciphertext),
				partyAmm: MpcCore.onBoard(self.partyAmm.ciphertext),
				partyBmm: MpcCore.onBoard(self.partyBmm.ciphertext),
				lf: MpcCore.onBoard(self.lf.ciphertext)
			});
	}

	/**
	 * @notice Converts a GarbledPrivateLockedValues struct to a PrivateLockedValues struct.
	 * @param self The GarbledPrivateLockedValues struct to be converted.
	 * @param encryptionAddress The encryption address of the party.
	 * @return The converted PrivateLockedValues struct.
	 */
	function offBoard(GarbledPrivateLockedValues memory self, address encryptionAddress) internal returns (PrivateLockedValues memory) {
		return
			PrivateLockedValues({
				cva: MpcCore.offBoardCombined(self.cva, encryptionAddress),
				partyAmm: MpcCore.offBoardCombined(self.partyAmm, encryptionAddress),
				partyBmm: MpcCore.offBoardCombined(self.partyBmm, encryptionAddress),
				lf: MpcCore.offBoardCombined(self.lf, encryptionAddress)
			});
	}

	/**
	 * @notice Adds the values of two GarbledPrivateLockedValues structs.
	 * @param self The GarbledPrivateLockedValues struct to which values will be added.
	 * @param a The GarbledPrivateLockedValues struct containing values to be added.
	 * @return The updated GarbledPrivateLockedValues struct.
	 */
	function add(GarbledPrivateLockedValues memory self, GarbledPrivateLockedValues memory a) internal returns (GarbledPrivateLockedValues memory) {
		return
			GarbledPrivateLockedValues({
				cva: self.cva.add(a.cva),
				partyAmm: self.partyAmm.add(a.partyAmm),
				partyBmm: self.partyBmm.add(a.partyBmm),
				lf: self.lf.add(a.lf)
			});
	}

	/**
	 * @notice Subtracts the values of two GarbledPrivateLockedValues structs.
	 * @param self The GarbledPrivateLockedValues struct from which values will be subtracted.
	 * @param a The GarbledPrivateLockedValues struct containing values to be subtracted.
	 * @return The updated GarbledPrivateLockedValues struct.
	 */
	function sub(GarbledPrivateLockedValues memory self, GarbledPrivateLockedValues memory a) internal returns (GarbledPrivateLockedValues memory) {
		return
			GarbledPrivateLockedValues({
				cva: self.cva.sub(a.cva),
				partyAmm: self.partyAmm.sub(a.partyAmm),
				partyBmm: self.partyBmm.sub(a.partyBmm),
				lf: self.lf.sub(a.lf)
			});
	}

	/**
	 * @notice Creates a zero GarbledPrivateLockedValues struct.
	 * @return A zero GarbledPrivateLockedValues struct.
	 */
	function makeZero() internal returns (GarbledPrivateLockedValues memory) {
		gtUint256 zero = MpcCore.setPublic256(uint256(0));
		return GarbledPrivateLockedValues({ cva: zero, partyAmm: zero, partyBmm: zero, lf: zero });
	}

	/**
	 * @notice Calculates the total encrypted locked balance for Party A.
	 * @param self The GarbledPrivateLockedValues struct containing locked values.
	 * @return The total encrypted locked balance for Party A.
	 */
	function totalForPartyA(GarbledPrivateLockedValues memory self) internal returns (gtUint256) {
		return self.cva.add(self.partyAmm).add(self.lf);
	}

	/**
	 * @notice Calculates the total encrypted locked balance for Party B.
	 * @param self The GarbledPrivateLockedValues struct containing locked values.
	 * @return The total encrypted locked balance for Party B.
	 */
	function totalForPartyB(GarbledPrivateLockedValues memory self) internal returns (gtUint256) {
		return self.cva.add(self.partyBmm).add(self.lf);
	}

	/**
	 * @notice Multiplies all values of an GarbledPrivateLockedValues struct by an encrypted scalar.
	 * @param self The GarbledPrivateLockedValues struct to be multiplied.
	 * @param a The encrypted scalar value to multiply by.
	 * @return The updated GarbledPrivateLockedValues struct.
	 */
	function mul(GarbledPrivateLockedValues memory self, gtUint256 a) internal returns (GarbledPrivateLockedValues memory) {
		return
			GarbledPrivateLockedValues({ cva: self.cva.mul(a), partyAmm: self.partyAmm.mul(a), partyBmm: self.partyBmm.mul(a), lf: self.lf.mul(a) });
	}

	/**
	 * @notice Multiplies all values of an GarbledPrivateLockedValues struct by a public scalar.
	 * @param self The GarbledPrivateLockedValues struct to be multiplied.
	 * @param a The public scalar value to multiply by.
	 * @return The updated GarbledPrivateLockedValues struct.
	 */
	function mulPublic(GarbledPrivateLockedValues memory self, uint256 a) internal returns (GarbledPrivateLockedValues memory) {
		gtUint256 encryptedScalar = MpcCore.setPublic256(a);
		return mul(self, encryptedScalar);
	}

	/**
	 * @notice Divides all values of an GarbledPrivateLockedValues struct by an encrypted scalar.
	 * @param self The GarbledPrivateLockedValues struct to be divided.
	 * @param a The encrypted scalar value to divide by.
	 * @return The updated GarbledPrivateLockedValues struct.
	 */
	function div(GarbledPrivateLockedValues memory self, gtUint256 a) internal returns (GarbledPrivateLockedValues memory) {
		self.cva = self.cva.div(a);
		self.partyAmm = self.partyAmm.div(a);
		self.partyBmm = self.partyBmm.div(a);
		self.lf = self.lf.div(a);
		return self;
	}

	/**
	 * @notice Divides all values of an GarbledPrivateLockedValues struct by a public scalar.
	 * @param self The GarbledPrivateLockedValues struct to be divided.
	 * @param a The public scalar value to divide by.
	 * @return The updated GarbledPrivateLockedValues struct.
	 */
	function divPublic(GarbledPrivateLockedValues memory self, uint256 a) internal returns (GarbledPrivateLockedValues memory) {
		gtUint256 encryptedScalar = MpcCore.setPublic256(a);
		return div(self, encryptedScalar);
	}

	/**
	 * @notice Checks if two GarbledPrivateLockedValues structs are equal.
	 * @param self The first GarbledPrivateLockedValues struct.
	 * @param other The second GarbledPrivateLockedValues struct.
	 * @return An encrypted boolean indicating equality.
	 */
	function eq(GarbledPrivateLockedValues memory self, GarbledPrivateLockedValues memory other) internal returns (gtBool) {
		gtBool cvaEq = self.cva.eq(other.cva);
		gtBool partyAmmEq = self.partyAmm.eq(other.partyAmm);
		gtBool partyBmmEq = self.partyBmm.eq(other.partyBmm);
		gtBool lfEq = self.lf.eq(other.lf);

		return cvaEq.and(partyAmmEq).and(partyBmmEq).and(lfEq);
	}

	/**
	 * @notice Performs conditional selection between two GarbledPrivateLockedValues structs.
	 * @param condition The encrypted boolean condition.
	 * @param trueValue The GarbledPrivateLockedValues to select if condition is true.
	 * @param falseValue The GarbledPrivateLockedValues to select if condition is false.
	 * @return The conditionally selected GarbledPrivateLockedValues struct.
	 */
	function mux(
		gtBool condition,
		GarbledPrivateLockedValues memory trueValue,
		GarbledPrivateLockedValues memory falseValue
	) internal returns (GarbledPrivateLockedValues memory) {
		return
			GarbledPrivateLockedValues({
				cva: MpcCore.mux(condition, trueValue.cva, falseValue.cva),
				partyAmm: MpcCore.mux(condition, trueValue.partyAmm, falseValue.partyAmm),
				partyBmm: MpcCore.mux(condition, trueValue.partyBmm, falseValue.partyBmm),
				lf: MpcCore.mux(condition, trueValue.lf, falseValue.lf)
			});
	}
}
