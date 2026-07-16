// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Pausable.sol";
import "../../utils/Accessibility.sol";
import "./ILiquidationFacet.sol";
import "./LiquidationFacetImpl.sol";
import "../../libraries/LibEncryption.sol";
import "../../libraries/LibOnChainUpnl.sol";
import "./DeferredLiquidationFacetImpl.sol";
import "../../storages/AccountStorage.sol";

contract LiquidationFacet is Pausable, Accessibility, ILiquidationFacet {
	/**
	 * @notice Liquidates Party A based on the provided signature.
	 * @param partyA The address of Party A to be liquidated.
	 * @param liquidationSig The Muon signature.
	 */
	function liquidatePartyA(
		address partyA,
		LiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused notLiquidatedPartyA(partyA) onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		LiquidationFacetImpl.liquidatePartyA(partyA, liquidationSig);
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		ctUint256 memory ctAllocatedBalance = accountLayout.allocatedBalances[partyA].userCiphertext;
		address encryptionAddress = LibAccount.getUserEncryptionAddress(partyA);

		(gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) = LibOnChainUpnl.partyAUpnlAndLossFromSymbolPrices(
			partyA,
			liquidationSig.symbolIds,
			liquidationSig.prices
		);
		ctInt256 memory ctUpnl = MpcCore.offBoardToUser(gtUpnl, encryptionAddress);
		ctInt256 memory ctTotalUnrealizedLoss = MpcCore.offBoardToUser(gtTotalUnrealizedLoss, encryptionAddress);

		emit LiquidatePartyA(msg.sender, partyA, ctAllocatedBalance, ctUpnl, ctTotalUnrealizedLoss, liquidationSig.liquidationId);
	}

	/**
	 * @notice Sets the prices of symbols at the time of liquidation.
	 * @dev The Muon signature here should be the same as the one that got partyA liquidated.
	 * @param partyA The address of Party A associated with the liquidation.
	 * @param liquidationSig The Muon signature containing symbol IDs and their corresponding prices.
	 */
	function setSymbolsPrice(
		address partyA,
		LiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		LiquidationFacetImpl.setSymbolsPrice(partyA, liquidationSig);
		address encryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		ctUint256[] memory encryptedPrices = new ctUint256[](liquidationSig.prices.length);
		for (uint256 i = 0; i < liquidationSig.prices.length; i++) {
			gtUint256 gtPrice = MpcCore.setPublic256(liquidationSig.prices[i]);
			encryptedPrices[i] = MpcCore.offBoardToUser(gtPrice, encryptionAddress);
		}
		emit SetSymbolsPrices(msg.sender, partyA, liquidationSig.symbolIds, encryptedPrices, liquidationSig.liquidationId);
	}

	/**
	 * @notice Deferred liquidates Party A based on the provided signature.
	 * @param partyA The address of Party A to be liquidated.
	 * @param liquidationSig The Muon signature.
	 */
	function deferredLiquidatePartyA(
		address partyA,
		DeferredLiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused notLiquidatedPartyA(partyA) onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		DeferredLiquidationFacetImpl.deferredLiquidatePartyA(partyA, liquidationSig);
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		ctUint256 memory ctAllocatedBalance = accountLayout.allocatedBalances[partyA].userCiphertext;
		address encryptionAddress = LibAccount.getUserEncryptionAddress(partyA);

		(gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) = LibOnChainUpnl.partyAUpnlAndLossFromSymbolPrices(
			partyA,
			liquidationSig.symbolIds,
			liquidationSig.prices
		);
		ctInt256 memory ctUpnl = MpcCore.offBoardToUser(gtUpnl, encryptionAddress);
		ctInt256 memory ctTotalUnrealizedLoss = MpcCore.offBoardToUser(gtTotalUnrealizedLoss, encryptionAddress);
		ctUint256 memory ctLiquidationAllocatedBalance = accountLayout.allocatedBalances[partyA].userCiphertext;

		emit DeferredLiquidatePartyA(
			msg.sender,
			partyA,
			ctAllocatedBalance,
			ctUpnl,
			ctTotalUnrealizedLoss,
			liquidationSig.liquidationId,
			liquidationSig.liquidationBlockNumber,
			liquidationSig.liquidationTimestamp,
			ctLiquidationAllocatedBalance
		);
	}

	/**
	 * @notice Deferred sets the prices of symbols at the time of liquidation.
	 * @dev The Muon signature here should be the same as the one that got partyA liquidated.
	 * @param partyA The address of Party A associated with the liquidation.
	 * @param liquidationSig The Muon signature containing symbol IDs and their corresponding prices.
	 */
	function deferredSetSymbolsPrice(
		address partyA,
		DeferredLiquidationSig memory liquidationSig
	) external whenNotLiquidationPaused onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		DeferredLiquidationFacetImpl.deferredSetSymbolsPrice(partyA, liquidationSig);
		address encryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		ctUint256[] memory encryptedPrices = new ctUint256[](liquidationSig.prices.length);
		for (uint256 i = 0; i < liquidationSig.prices.length; i++) {
			gtUint256 gtPrice = MpcCore.setPublic256(liquidationSig.prices[i]);
			encryptedPrices[i] = MpcCore.offBoardToUser(gtPrice, encryptionAddress);
		}
		emit SetSymbolsPrices(msg.sender, partyA, liquidationSig.symbolIds, encryptedPrices, liquidationSig.liquidationId);
	}

	/**
	 * @notice Liquidates Party B with respect to a Party A.
	 * @param partyB The address of Party B to be liquidated.
	 * @param partyA The address of Party A related to the liquidation.
	 * @param upnlSig The Muon signature containing the unrealized profit and loss data.
	 */
	function liquidatePartyB(
		address partyB,
		address partyA,
		SingleUpnlSig memory upnlSig
	) external whenNotLiquidationPaused notLiquidatedPartyB(partyB, partyA) notLiquidatedPartyA(partyA) onlyRole(LibAccessibility.LIQUIDATOR_ROLE) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		ctUint256 memory ctPartyBAllocatedBalance = accountLayout.partyBAllocatedBalances[partyB][partyA].userCiphertext;
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
		gtInt256 gtUpnl = LibOnChainUpnl.partyBUpnlFromQuotePrices(partyB, partyA, LibOnChainUpnl.priceSigFromSingle(upnlSig));
		ctInt256 memory ctUpnl = MpcCore.offBoardToUser(gtUpnl, partyBEncryptionAddress);

		emit LiquidatePartyB(msg.sender, partyB, partyA, ctPartyBAllocatedBalance, ctUpnl);
		emit ObserverLiquidatePartyB(
			msg.sender,
			partyB,
			partyA,
			accountLayout.observerPartyBAllocatedBalances[partyB][partyA],
			LibEncryption.offBoardToObserver(gtUpnl)
		);
		LiquidationFacetImpl.liquidatePartyB(partyB, partyA, upnlSig);
	}
}
