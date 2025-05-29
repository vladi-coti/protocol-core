// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibPrivateQuote.sol";
import "../../storages/QuoteStorage.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PrivateQuoteFacet is Accessibility, Pausable {
	/**
	 * @notice Enables private mode for a quote
	 * @param quoteId The ID of the quote to enable private mode for
	 */
	function enablePrivateMode(uint256 quoteId) external whenNotGlobalPaused {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can enable private mode");
		require(!LibPrivateQuote.isPrivateQuote(quoteId), "PrivateQuoteFacet: Quote already in private mode");

		LibPrivateQuote.enablePrivateMode(quoteId, msg.sender);
	}

	/**
	 * @notice Checks if a quote is using private variables
	 * @param quoteId The ID of the quote to check
	 * @return True if the quote uses private variables
	 */
	function isPrivateQuote(uint256 quoteId) external view returns (bool) {
		return LibPrivateQuote.isPrivateQuote(quoteId);
	}

	/**
	 * @notice Gets the private quantity for a quote (only accessible by quote parties)
	 * @param quoteId The ID of the quote
	 * @return The quantity (decrypted if caller is authorized)
	 */
	function getPrivateQuantity(uint256 quoteId) external view returns (uint256) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can access private data");

		return LibPrivateQuote.getPrivateQuantity(quoteId);
	}

	/**
	 * @notice Gets the private closed amount for a quote (only accessible by quote parties)
	 * @param quoteId The ID of the quote
	 * @return The closed amount (decrypted if caller is authorized)
	 */
	function getPrivateClosedAmount(uint256 quoteId) external view returns (uint256) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can access private data");

		return LibPrivateQuote.getPrivateClosedAmount(quoteId);
	}

	/**
	 * @notice Gets the private partyA address for a quote (only accessible by quote parties)
	 * @param quoteId The ID of the quote
	 * @return The partyA address (decrypted if caller is authorized)
	 */
	function getPrivatePartyA(uint256 quoteId) external view returns (address) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can access private data");

		return LibPrivateQuote.getPrivatePartyA(quoteId);
	}

	/**
	 * @notice Gets the private partyB address for a quote (only accessible by quote parties)
	 * @param quoteId The ID of the quote
	 * @return The partyB address (decrypted if caller is authorized)
	 */
	function getPrivatePartyB(uint256 quoteId) external view returns (address) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can access private data");

		return LibPrivateQuote.getPrivatePartyB(quoteId);
	}

	/**
	 * @notice Gets the open amount for a quote (quantity - closedAmount)
	 * @param quoteId The ID of the quote
	 * @return The open amount
	 */
	function getPrivateOpenAmount(uint256 quoteId) external view returns (uint256) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can access private data");

		return LibPrivateQuote.quoteOpenAmount(quoteId);
	}

	/**
	 * @notice Batch enable private mode for multiple quotes
	 * @param quoteIds Array of quote IDs to enable private mode for
	 */
	function batchEnablePrivateMode(uint256[] calldata quoteIds) external whenNotGlobalPaused {
		for (uint256 i = 0; i < quoteIds.length; i++) {
			Quote storage quote = QuoteStorage.layout().quotes[quoteIds[i]];
			require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can enable private mode");

			if (!LibPrivateQuote.isPrivateQuote(quoteIds[i])) {
				LibPrivateQuote.enablePrivateMode(quoteIds[i], msg.sender);
			}
		}
	}
}
