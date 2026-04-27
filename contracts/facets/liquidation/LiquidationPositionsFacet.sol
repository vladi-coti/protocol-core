// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/QuoteStorage.sol";
import "../../utils/Pausable.sol";
import "../../utils/Accessibility.sol";
import "./ILiquidationPositionsFacet.sol";
import "./LiquidationFacetImpl.sol";

contract LiquidationPositionsFacet is Pausable, Accessibility, ILiquidationPositionsFacet {
	/**
	 * @notice Liquidates pending positions of Party A.
	 * @param partyA The address of Party A whose pending positions will be liquidated.
	 */
	function liquidatePendingPositionsPartyA(address partyA) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		uint256[] memory pendingQuotes = quoteLayout.partyAPendingQuotes[partyA];
		(ctUint256[] memory liquidatedAmounts, bytes memory liquidationId) = LiquidationFacetImpl.liquidatePendingPositionsPartyA(partyA);
		emit LiquidatePendingPositionsPartyA(msg.sender, partyA, pendingQuotes, liquidatedAmounts, liquidationId);
	}

	/**
	 * @notice Liquidates other positions of Party A.
	 * @param partyA The address of Party A whose positions will be liquidated.
	 * @param quoteIds An array of quote IDs representing the positions to be liquidated.
	 */
	function liquidatePositionsPartyA(
		address partyA,
		uint256[] memory quoteIds
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		(bool disputed, ctUint256[] memory liquidatedAmounts, uint256[] memory closeIds, bytes memory liquidationId) = LiquidationFacetImpl
			.liquidatePositionsPartyA(partyA, quoteIds);
		emit LiquidatePositionsPartyA(msg.sender, partyA, quoteIds, liquidatedAmounts, closeIds, liquidationId);
		if (disputed) {
			emit LiquidationDisputed(partyA, liquidationId);
		}
	}

	/**
	 * @notice Liquidates positions of Party B the Party A.
	 * @param partyB The address of Party B whose positions are being liquidated.
	 * @param partyA The address of Party A related to the liquidation.
	 * @param priceSig The Muon signature containing the quote price data.
	 */
	function liquidatePositionsPartyB(
		address partyB,
		address partyA,
		QuotePriceSig memory priceSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		(ctUint256[] memory liquidatedAmounts, uint256[] memory closeIds) = LiquidationFacetImpl.liquidatePositionsPartyB(partyB, partyA, priceSig);
		emit LiquidatePositionsPartyB(msg.sender, partyB, partyA, priceSig.quoteIds, liquidatedAmounts, closeIds);
		if (QuoteStorage.layout().partyBPositionsCount[partyB][partyA] == 0) {
			emit FullyLiquidatedPartyB(partyB, partyA);
		}
	}
}
