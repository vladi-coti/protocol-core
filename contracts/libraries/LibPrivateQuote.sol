// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../utils/mpc/MpcCore.sol";
import "../storages/QuoteStorage.sol";
import "../storages/PrivateQuoteStorage.sol";

library LibPrivateQuote {
	/**
	 * @notice Sets the private quantity for a quote
	 * @param quoteId The ID of the quote
	 * @param quantity The quantity to encrypt and store
	 * @param userAddress The address to encrypt for (partyA or partyB)
	 */
	function setPrivateQuantity(uint256 quoteId, uint256 quantity, address userAddress) internal {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		// Convert to gtUint64 and encrypt for the user
		gtUint64 gtQuantity = MpcCore.setPublic64(uint64(quantity));
		layout.privateQuantities[quoteId] = MpcCore.offBoardCombined(gtQuantity, userAddress);
	}

	/**
	 * @notice Gets the private quantity for a quote
	 * @param quoteId The ID of the quote
	 * @return The decrypted quantity
	 */
	function getPrivateQuantity(uint256 quoteId) internal returns (uint256) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		if (ctUint64.unwrap(layout.privateQuantities[quoteId].ciphertext) == 0) {
			// Fallback to public quantity if private not set
			return QuoteStorage.layout().quotes[quoteId].quantity;
		}

		gtUint64 gtQuantity = MpcCore.onBoard(layout.privateQuantities[quoteId].ciphertext);
		return uint256(MpcCore.decrypt(gtQuantity));
	}

	/**
	 * @notice Sets the private closed amount for a quote
	 * @param quoteId The ID of the quote
	 * @param closedAmount The closed amount to encrypt and store
	 * @param userAddress The address to encrypt for
	 */
	function setPrivateClosedAmount(uint256 quoteId, uint256 closedAmount, address userAddress) internal {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		gtUint64 gtClosedAmount = MpcCore.setPublic64(uint64(closedAmount));
		layout.privateClosedAmounts[quoteId] = MpcCore.offBoardCombined(gtClosedAmount, userAddress);
	}

	/**
	 * @notice Gets the private closed amount for a quote
	 * @param quoteId The ID of the quote
	 * @return The decrypted closed amount
	 */
	function getPrivateClosedAmount(uint256 quoteId) internal returns (uint256) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		if (ctUint64.unwrap(layout.privateClosedAmounts[quoteId].ciphertext) == 0) {
			// Fallback to public closed amount if private not set
			return QuoteStorage.layout().quotes[quoteId].closedAmount;
		}

		gtUint64 gtClosedAmount = MpcCore.onBoard(layout.privateClosedAmounts[quoteId].ciphertext);
		return uint256(MpcCore.decrypt(gtClosedAmount));
	}

	/**
	 * @notice Sets private party addresses (encrypted)
	 * @param quoteId The ID of the quote
	 * @param partyA The partyA address to encrypt
	 * @param partyB The partyB address to encrypt
	 * @param encryptionAddress The address to encrypt for
	 */
	function setPrivateParties(uint256 quoteId, address partyA, address partyB, address encryptionAddress) internal {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		// Convert addresses to uint256 for encryption
		gtUint64 gtPartyA = MpcCore.setPublic64(uint64(uint256(uint160(partyA))));
		gtUint64 gtPartyB = MpcCore.setPublic64(uint64(uint256(uint160(partyB))));

		layout.privatePartyA[quoteId] = MpcCore.offBoardCombined(gtPartyA, encryptionAddress);
		layout.privatePartyB[quoteId] = MpcCore.offBoardCombined(gtPartyB, encryptionAddress);
	}

	/**
	 * @notice Gets the private partyA address
	 * @param quoteId The ID of the quote
	 * @return The decrypted partyA address
	 */
	function getPrivatePartyA(uint256 quoteId) internal returns (address) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		if (ctUint64.unwrap(layout.privatePartyA[quoteId].ciphertext) == 0) {
			// Fallback to public partyA if private not set
			return QuoteStorage.layout().quotes[quoteId].partyA;
		}

		gtUint64 gtPartyA = MpcCore.onBoard(layout.privatePartyA[quoteId].ciphertext);
		return address(uint160(uint256(MpcCore.decrypt(gtPartyA))));
	}

	/**
	 * @notice Gets the private partyB address
	 * @param quoteId The ID of the quote
	 * @return The decrypted partyB address
	 */
	function getPrivatePartyB(uint256 quoteId) internal returns (address) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		if (ctUint64.unwrap(layout.privatePartyB[quoteId].ciphertext) == 0) {
			// Fallback to public partyB if private not set
			return QuoteStorage.layout().quotes[quoteId].partyB;
		}

		gtUint64 gtPartyB = MpcCore.onBoard(layout.privatePartyB[quoteId].ciphertext);
		return address(uint160(uint256(MpcCore.decrypt(gtPartyB))));
	}

	/**
	 * @notice Checks if a quote uses private variables
	 * @param quoteId The ID of the quote
	 * @return True if the quote has private variables enabled
	 */
	function isPrivateQuote(uint256 quoteId) internal view returns (bool) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();
		return ctUint64.unwrap(layout.privateQuantities[quoteId].ciphertext) != 0;
	}

	/**
	 * @notice Calculates the open amount for a quote (quantity - closedAmount)
	 * @param quoteId The ID of the quote
	 * @return The open amount
	 */
	function quoteOpenAmount(uint256 quoteId) internal returns (uint256) {
		uint256 quantity = getPrivateQuantity(quoteId);
		uint256 closedAmount = getPrivateClosedAmount(quoteId);
		return quantity - closedAmount;
	}

	/**
	 * @notice Enables private mode for a quote
	 * @param quoteId The ID of the quote
	 * @param userAddress The address to encrypt for
	 */
	function enablePrivateMode(uint256 quoteId, address userAddress) internal {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		// Copy existing public values to private storage
		setPrivateQuantity(quoteId, quote.quantity, userAddress);
		setPrivateClosedAmount(quoteId, quote.closedAmount, userAddress);
		setPrivateParties(quoteId, quote.partyA, quote.partyB, userAddress);
	}
}
