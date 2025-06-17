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
	function getPrivateQuantity(uint256 quoteId) external returns (uint256) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];
		require(msg.sender == quote.partyA || msg.sender == quote.partyB, "PrivateQuoteFacet: Only quote parties can access private data");

		return LibPrivateQuote.getPrivateQuantity(quoteId);
	}
}
