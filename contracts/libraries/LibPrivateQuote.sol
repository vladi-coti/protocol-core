// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/QuoteStorage.sol";
import "../storages/PrivateQuoteStorage.sol";

library LibPrivateQuote {
	/**
	 * @notice Creates a private quote with encrypted parameters
	 * @param quoteId The ID of the quote
	 * @param encryptedQuantity Encrypted quantity for partyB
	 * @param encryptedPrice Encrypted price for partyB
	 * @param encryptedCva Encrypted CVA for partyB
	 * @param encryptedLf Encrypted LF for partyB
	 * @param encryptedPartyAmm Encrypted partyA MM for partyB
	 * @param encryptedPartyBmm Encrypted partyB MM for partyB
	 * @param partyA The partyA address
	 * @param partyB The partyB address (can be address(0) for whitelisted quotes)
	 */
	function createPrivateQuote(
		uint256 quoteId,
		itUint256 calldata encryptedQuantity,
		itUint256 calldata encryptedPrice,
		itUint256 calldata encryptedCva,
		itUint256 calldata encryptedLf,
		itUint256 calldata encryptedPartyAmm,
		itUint256 calldata encryptedPartyBmm,
		address partyA,
		address partyB
	) internal {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		// Validate and store encrypted parameters for partyB decryption
		gtUint256 memory gtQuantity = MpcCore.validateCiphertext(encryptedQuantity);
		gtUint256 memory gtPrice = MpcCore.validateCiphertext(encryptedPrice);
		gtUint256 memory gtCva = MpcCore.validateCiphertext(encryptedCva);
		gtUint256 memory gtLf = MpcCore.validateCiphertext(encryptedLf);
		gtUint256 memory gtPartyAmm = MpcCore.validateCiphertext(encryptedPartyAmm);
		gtUint256 memory gtPartyBmm = MpcCore.validateCiphertext(encryptedPartyBmm);

		// Store encrypted for partyB (so they can decrypt and process)
		if (partyB != address(0)) {
			layout.privateQuantities[quoteId] = MpcCore.offBoard(gtQuantity);
		}

		layout.encryptedQuantities[quoteId] = MpcCore.offBoard(gtQuantity);
		layout.encryptedPrice[quoteId] = MpcCore.offBoard(gtPrice);
		layout.encryptedCva[quoteId] = MpcCore.offBoard(gtCva);
		layout.encryptedLf[quoteId] = MpcCore.offBoard(gtLf);
		layout.encryptedPartyAmm[quoteId] = MpcCore.offBoard(gtPartyAmm);
		layout.encryptedPartyBmm[quoteId] = MpcCore.offBoard(gtPartyBmm);

		// Mark as private
		layout.isPrivateEnabled[quoteId] = true;
	}

	/**
	 * @notice Gets system-encrypted parameters for calculations
	 * @param quoteId The ID of the quote
	 * @return quantity The system-decrypted quantity
	 * @return price The system-decrypted price
	 * @return cva The system-decrypted CVA
	 * @return lf The system-decrypted LF
	 * @return partyAmm The system-decrypted partyA MM
	 * @return partyBmm The system-decrypted partyB MM
	 */
	function getSystemDecryptedParameters(
		uint256 quoteId
	) internal returns (uint256 quantity, uint256 price, uint256 cva, uint256 lf, uint256 partyAmm, uint256 partyBmm) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		// Decrypt system-encrypted parameters
		if (layout.isPrivateEnabled[quoteId]) {
			gtUint256 memory gtQuantity = MpcCore.onBoard(layout.encryptedQuantities[quoteId]);
			gtUint256 memory gtPrice = MpcCore.onBoard(layout.encryptedPrice[quoteId]);
			gtUint256 memory gtCva = MpcCore.onBoard(layout.encryptedCva[quoteId]);
			gtUint256 memory gtLf = MpcCore.onBoard(layout.encryptedLf[quoteId]);
			gtUint256 memory gtPartyAmm = MpcCore.onBoard(layout.encryptedPartyAmm[quoteId]);
			gtUint256 memory gtPartyBmm = MpcCore.onBoard(layout.encryptedPartyBmm[quoteId]);

			quantity = uint256(MpcCore.decrypt(gtQuantity));
			price = uint256(MpcCore.decrypt(gtPrice));
			cva = uint256(MpcCore.decrypt(gtCva));
			lf = uint256(MpcCore.decrypt(gtLf));
			partyAmm = uint256(MpcCore.decrypt(gtPartyAmm));
			partyBmm = uint256(MpcCore.decrypt(gtPartyBmm));
		} else {
			// Fallback to public data if not encrypted
			Quote storage quote = QuoteStorage.layout().quotes[quoteId];
			quantity = quote.quantity;
			price = quote.requestedOpenPrice;
			cva = quote.lockedValues.cva;
			lf = quote.lockedValues.lf;
			partyAmm = quote.lockedValues.partyAmm;
			partyBmm = quote.lockedValues.partyBmm;
		}
	}

	/**
	 * @notice Gets the private quantity for a quote
	 * @param quoteId The ID of the quote
	 * @return The decrypted quantity
	 */
	function getPrivateQuantity(uint256 quoteId) internal returns (uint256) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		if (layout.isPrivateEnabled[quoteId]) {
			// Decrypt the system-encrypted quantity
			gtUint256 memory gtQuantity = MpcCore.onBoard(layout.encryptedQuantities[quoteId]);
			return uint256(MpcCore.decrypt(gtQuantity));
		} else {
			// Fallback to public data
			return QuoteStorage.layout().quotes[quoteId].quantity;
		}
	}

	/**
	 * @notice Sets the private quantity for a quote (used in partial fills)
	 * @param quoteId The ID of the quote
	 * @param newQuantity The new quantity value
	 * @param userAddress The address authorized to decrypt (typically partyA)
	 */
	function setPrivateQuantity(uint256 quoteId, uint256 newQuantity, address userAddress) internal {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();

		if (layout.isPrivateEnabled[quoteId]) {
			// Encrypt the new quantity for system use
			gtUint256 memory gtNewQuantity = MpcCore.setPublic256(newQuantity);
			layout.encryptedQuantities[quoteId] = MpcCore.offBoard(gtNewQuantity);

			// Also encrypt for user if needed
			if (userAddress != address(0)) {
				layout.privateQuantities[quoteId] = MpcCore.offBoard(gtNewQuantity);
			}
		} else {
			// Update public quantity as fallback
			QuoteStorage.layout().quotes[quoteId].quantity = newQuantity;
		}
	}

	/**
	 * @notice Checks if a quote uses private variables
	 * @param quoteId The ID of the quote
	 * @return True if the quote has private variables enabled
	 */
	function isPrivateQuote(uint256 quoteId) internal view returns (bool) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();
		return layout.isPrivateEnabled[quoteId];
	}

	/**
	 * @notice Checks if a quote was created as a private quote (vs converted later)
	 * @param quoteId The ID of the quote
	 * @return True if the quote was created with system encryption
	 */
	function isSystemEncryptedQuote(uint256 quoteId) internal view returns (bool) {
		PrivateQuoteStorage.Layout storage layout = PrivateQuoteStorage.layout();
		return layout.isPrivateEnabled[quoteId];
	}
}
