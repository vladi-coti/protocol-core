// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibLockedValues.sol";
import "../../libraries/muon/LibMuonLiquidation.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibLiquidation.sol";
import "../../libraries/SharedEvents.sol";
import "../../libraries/LibEncryption.sol";
import "../../libraries/LibOnChainUpnl.sol";
import "../../storages/MAStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library DeferredLiquidationFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function _storeLiquidationDeficit(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) private {
		LibEncryption.storeLiquidationDeficit(accountLayout, partyA, value);
	}

	function _storeLiquidationFee(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) private {
		LibEncryption.storeLiquidationFee(accountLayout, partyA, value);
	}

	function deferredLiquidatePartyA(address partyA, DeferredLiquidationSig memory liquidationSig) internal {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LibMuonLiquidation.verifyDeferredLiquidationSig(liquidationSig, partyA);

		(gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) = LibOnChainUpnl.partyAUpnlAndLossFromSymbolPrices(partyA, liquidationSig.symbolIds, liquidationSig.prices);
		// H-16: insolvency from signed allocated snapshot + on-chain UPNL (not current allocated).
		gtInt256 gtLiquidationAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			gtUpnl,
			liquidationSig.liquidationAllocatedBalance,
			partyA
		);
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtLiquidationAvailableBalance.lt(gtZero)), "LiquidationFacet: PartyA is solvent");

		gtInt256 gtAvailableBalance = gtLiquidationAvailableBalance;
		if (MpcCore.decrypt(gtAvailableBalance.gt(gtZero))) {
			// Update allocated balance with encrypted operations
			gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAvailableBalanceAmount = gtAvailableBalance.fromSigned();
			gtUint256 gtNewBalance = gtCurrentBalance.checkedSub(gtAvailableBalanceAmount);
			LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtNewBalance);
			
			gtUint256 gtCurrentReimbursement = LibAccount.initializePartyAReimbursement(partyA);
			gtUint256 gtNewReimbursement = gtCurrentReimbursement.checkedAdd(gtAvailableBalanceAmount);
			LibEncryption.storePartyAReimbursement(accountLayout, partyA, gtNewReimbursement);
		}

		maLayout.liquidationStatus[partyA] = true;
		accountLayout.liquidationDetails[partyA] = LiquidationDetail({
			liquidationId: liquidationSig.liquidationId,
			liquidationType: LiquidationType.NONE,
			upnl: LibEncryption.offBoardToUser(gtUpnl, LibAccount.getUserEncryptionAddress(partyA)),
			totalUnrealizedLoss: LibEncryption.offBoardToUser(gtTotalUnrealizedLoss, LibAccount.getUserEncryptionAddress(partyA)),
			deficit: 0,
			liquidationFee: 0,
			timestamp: liquidationSig.timestamp,
			involvedPartyBCounts: 0,
			partyAAccumulatedUpnl: 0,
			disputed: false,
			liquidationTimestamp: liquidationSig.liquidationTimestamp
		});
		LibEncryption.storeIntForAddress(
			accountLayout.settlementStates[partyA][address(0)].actualAmount,
			accountLayout.observerSettlementStates[partyA][address(0)].actualAmount,
			MpcCore.setPublic256(int256(0)),
			LibAccount.getUserEncryptionAddress(partyA)
		);
		accountLayout.liquidators[partyA].push(msg.sender);
	}

	function deferredSetSymbolsPrice(address partyA, DeferredLiquidationSig memory liquidationSig) internal {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LibMuonLiquidation.verifyDeferredLiquidationSig(liquidationSig, partyA);
		require(maLayout.liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");

		LiquidationDetail storage detail = accountLayout.liquidationDetails[partyA];
		require(keccak256(detail.liquidationId) == keccak256(liquidationSig.liquidationId), "LiquidationFacet: Invalid liquidationId");

		for (uint256 index = 0; index < liquidationSig.symbolIds.length; index++) {
			uint256 symbolId = liquidationSig.symbolIds[index];
			accountLayout.symbolsPrices[partyA][symbolId] = Price(liquidationSig.prices[index], detail.timestamp);
			accountLayout.symbolPriceLiquidationId[partyA][symbolId] = keccak256(liquidationSig.liquidationId);
		}

		(gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) = LibOnChainUpnl.partyAUpnlAndLossFromSymbolPrices(partyA, liquidationSig.symbolIds, liquidationSig.prices);
		// H-16: type classification must use the same allocated snapshot as the prove step.
		gtInt256 gtAvailableBalance2 = LibAccount.partyAAvailableBalanceForLiquidation(
			gtUpnl,
			liquidationSig.liquidationAllocatedBalance,
			partyA
		);
		detail.totalUnrealizedLoss = LibEncryption.offBoardToUser(gtTotalUnrealizedLoss, LibAccount.getUserEncryptionAddress(partyA));
		if (detail.liquidationType == LiquidationType.NONE) {
			gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].lf.ciphertext);
			gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
			gtUint256 gtDeficitMagnitude = MpcCore.setPublic256(int256(0)).checkedSub(gtAvailableBalance2).fromSigned();
			gtBool gtNormal = gtDeficitMagnitude.lt(gtLf);
			gtBool gtLate = gtDeficitMagnitude.le(gtLf.checkedAdd(gtCva));
			
			if (MpcCore.decrypt(gtNormal)) {
				detail.liquidationType = LiquidationType.NORMAL;
				_storeLiquidationFee(accountLayout, partyA, gtLf.checkedSub(gtDeficitMagnitude));
			} else if (MpcCore.decrypt(gtLate)) {
				detail.liquidationType = LiquidationType.LATE;
				_storeLiquidationDeficit(accountLayout, partyA, gtDeficitMagnitude.checkedSub(gtLf));
			} else {
				detail.liquidationType = LiquidationType.OVERDUE;
				_storeLiquidationDeficit(accountLayout, partyA, gtDeficitMagnitude.checkedSub(gtLf).checkedSub(gtCva));
			}
			accountLayout.liquidators[partyA].push(msg.sender);
		}
	}
}
