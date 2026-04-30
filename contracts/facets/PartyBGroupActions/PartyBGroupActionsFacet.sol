// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPartyBGroupActionsFacet.sol";
import "./PartyBGroupActionsFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";

contract PartyBGroupActionsFacet is Accessibility, Pausable, IPartyBGroupActionsFacet {

	/**
	 * @notice Locks and opens the specified quote with the provided details and signatures.
	 * @param quoteId The ID of the quote to be locked and opened.
	 * @param encryptedParams Struct containing encrypted filledAmount and openedPrice parameters.
	 * @param upnlSig The Muon signature containing the single UPNL value used to lock the quote.
	 * @param pairUpnlSig The Muon signature containing the pair UPNL and price values used to open the position.
	 */
	function lockAndOpenQuote(
		uint256 quoteId,
		PrivateOpenPositionParams calldata encryptedParams,
		SingleUpnlSig memory upnlSig,
		PairUpnlAndPriceSig memory pairUpnlSig
	) external override whenNotPartyBActionsPaused onlyPartyB notLiquidated(quoteId) {
		PartyBGroupActionsFacetImpl.lockAndOpenQuote(quoteId, encryptedParams, upnlSig, pairUpnlSig);
	}
}
