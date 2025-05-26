// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// COTI v2 MPC types
type gtUint64 is uint256;
type ctUint64 is uint256;
type itUint64 is uint256;
type gtBool is uint256;

struct utUint64 {
	ctUint64 ciphertext;
	ctUint64 userCiphertext;
}

/**
 * @dev MpcCore library for COTI v2 MPC operations
 * This is a simplified interface based on COTI's MPC functionality
 */
library MpcCore {
	/**
	 * @dev Sets a public value as gtUint64
	 */
	function setPublic64(uint64 value) internal pure returns (gtUint64) {
		return gtUint64.wrap(uint256(value));
	}

	/**
	 * @dev Sets a public boolean value
	 */
	function setPublic(bool value) internal pure returns (gtBool) {
		return gtBool.wrap(value ? 1 : 0);
	}

	/**
	 * @dev Validates a ciphertext input
	 */
	function validateCiphertext(itUint64 value) internal pure returns (gtUint64) {
		return gtUint64.wrap(itUint64.unwrap(value));
	}

	/**
	 * @dev Converts onboard ciphertext to garbled value
	 */
	function onBoard(ctUint64 value) internal pure returns (gtUint64) {
		return gtUint64.wrap(ctUint64.unwrap(value));
	}

	/**
	 * @dev Converts garbled value to offboard ciphertext
	 */
	function offBoard(gtUint64 value) internal pure returns (ctUint64) {
		return ctUint64.wrap(gtUint64.unwrap(value));
	}

	/**
	 * @dev Converts garbled value to user-specific ciphertext
	 */
	function offBoardToUser(gtUint64 value, address user) internal pure returns (ctUint64) {
		// In a real implementation, this would encrypt for the specific user
		// For now, we'll use a simple transformation
		return ctUint64.wrap(gtUint64.unwrap(value) ^ uint256(uint160(user)));
	}

	/**
	 * @dev Converts garbled value to combined user and contract ciphertext
	 */
	function offBoardCombined(gtUint64 value, address user) internal pure returns (utUint64 memory) {
		ctUint64 ciphertext = offBoard(value);
		ctUint64 userCiphertext = offBoardToUser(value, user);
		return utUint64(ciphertext, userCiphertext);
	}

	/**
	 * @dev Decrypts a garbled value (only for authorized parties)
	 */
	function decrypt(gtUint64 value) internal pure returns (uint64) {
		return uint64(gtUint64.unwrap(value));
	}

	/**
	 * @dev Adds two garbled values
	 */
	function add(gtUint64 a, gtUint64 b) internal pure returns (gtUint64) {
		return gtUint64.wrap(gtUint64.unwrap(a) + gtUint64.unwrap(b));
	}

	/**
	 * @dev Subtracts two garbled values
	 */
	function sub(gtUint64 a, gtUint64 b) internal pure returns (gtUint64) {
		return gtUint64.wrap(gtUint64.unwrap(a) - gtUint64.unwrap(b));
	}

	/**
	 * @dev Multiplies two garbled values
	 */
	function mul(gtUint64 a, gtUint64 b) internal pure returns (gtUint64) {
		return gtUint64.wrap(gtUint64.unwrap(a) * gtUint64.unwrap(b));
	}

	/**
	 * @dev Divides two garbled values
	 */
	function div(gtUint64 a, gtUint64 b) internal pure returns (gtUint64) {
		return gtUint64.wrap(gtUint64.unwrap(a) / gtUint64.unwrap(b));
	}

	/**
	 * @dev Compares if a equals b
	 */
	function eq(gtUint64 a, gtUint64 b) internal pure returns (gtBool) {
		return gtBool.wrap(gtUint64.unwrap(a) == gtUint64.unwrap(b) ? 1 : 0);
	}

	/**
	 * @dev Compares if a is less than b
	 */
	function lt(gtUint64 a, gtUint64 b) internal pure returns (gtBool) {
		return gtBool.wrap(gtUint64.unwrap(a) < gtUint64.unwrap(b) ? 1 : 0);
	}

	/**
	 * @dev Logical OR operation
	 */
	function or(gtBool a, gtBool b) internal pure returns (gtBool) {
		return gtBool.wrap((gtBool.unwrap(a) != 0 || gtBool.unwrap(b) != 0) ? 1 : 0);
	}

	/**
	 * @dev Multiplexer operation (if condition then a else b)
	 */
	function mux(gtBool condition, gtUint64 a, gtUint64 b) internal pure returns (gtUint64) {
		return gtBool.unwrap(condition) != 0 ? a : b;
	}

	/**
	 * @dev Transfer operation with balance checks
	 */
	function transfer(
		gtUint64 fromBalance,
		gtUint64 toBalance,
		gtUint64 amount
	) internal pure returns (gtUint64 newFromBalance, gtUint64 newToBalance, gtBool success) {
		gtBool hasEnoughBalance = gtBool.wrap(gtUint64.unwrap(fromBalance) >= gtUint64.unwrap(amount) ? 1 : 0);

		if (gtBool.unwrap(hasEnoughBalance) != 0) {
			newFromBalance = sub(fromBalance, amount);
			newToBalance = add(toBalance, amount);
			success = setPublic(true);
		} else {
			newFromBalance = fromBalance;
			newToBalance = toBalance;
			success = setPublic(false);
		}
	}
}
