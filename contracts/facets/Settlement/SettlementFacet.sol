// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./ISettlementFacet.sol";
import "../../libraries/LibAccessibility.sol";
import "../../libraries/LibAccessibility.sol";
import "../../storages/MuonStorage.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./SettlementFacetImpl.sol";

contract SettlementFacet is Accessibility, Pausable, ISettlementFacet {
	/**
	 * @notice Allows Party B to settle the upnl of party A position for the specified quotes.
	 * @param settlementSig The data struct contains quoteIds and upnl of parties and market prices
	 * @param updatedPrices New prices to be set as openedPrice for the specified quotes.
	 * @param partyA Address of party A
	 */
	function settleUpnl(
		SettlementSig memory settlementSig,
		uint256[] memory updatedPrices,
		address partyA
	) external whenNotPartyBActionsPaused onlyPartyB notLiquidatedPartyA(partyA) {
		utUint256[] memory newPartyBsAllocatedBalances = SettlementFacetImpl.settleUpnl(settlementSig, updatedPrices, partyA);
		
		// Decrypt the allocated balance for the event
		gtUint256 gtAllocatedBalance = LockedValuesOps.safeOnboard(AccountStorage.layout().allocatedBalances[partyA].ciphertext);
		uint256 allocatedBalance = MpcCore.decrypt(gtAllocatedBalance);
		
		// Convert utUint256[] to uint256[] for the event
		uint256[] memory decryptedBalances = new uint256[](newPartyBsAllocatedBalances.length);
		for (uint256 i = 0; i < newPartyBsAllocatedBalances.length; i++) {
			gtUint256 gtBalance = LockedValuesOps.safeOnboard(newPartyBsAllocatedBalances[i].ciphertext);
			decryptedBalances[i] = MpcCore.decrypt(gtBalance);
		}
		
		emit SettleUpnl(
			settlementSig.quotesSettlementsData,
			updatedPrices,
			partyA,
			allocatedBalance,
			decryptedBalances
		);
	}
}
