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
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		accountLayout.encryptedLiquidationDeficit[partyA] = MpcCore.offBoardCombined(value, partyAEncryptionAddress);
		accountLayout.observerEncryptedLiquidationDeficit[partyA] = LibEncryption.offBoardToObserver(value);
	}

	function _storeLiquidationFee(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) private {
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		accountLayout.encryptedLiquidationFee[partyA] = MpcCore.offBoardCombined(value, partyAEncryptionAddress);
		accountLayout.observerEncryptedLiquidationFee[partyA] = LibEncryption.offBoardToObserver(value);
	}

	function deferredLiquidatePartyA(address partyA, DeferredLiquidationSig memory liquidationSig) internal {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LibMuonLiquidation.verifyDeferredLiquidationSig(liquidationSig, partyA);

		gtInt256 gtLiquidationAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			liquidationSig.upnl,
			liquidationSig.liquidationAllocatedBalance,
			partyA
		);
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtLiquidationAvailableBalance.lt(gtZero)), "LiquidationFacet: PartyA is solvent");

		gtInt256 gtAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			liquidationSig.upnl,
			partyA
		);
		if (MpcCore.decrypt(gtAvailableBalance.gt(gtZero))) {
			// Update allocated balance with encrypted operations
			gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAvailableBalanceAmount = gtAvailableBalance.fromSigned();
			gtUint256 gtNewBalance = gtCurrentBalance.checkedSub(gtAvailableBalanceAmount);
			LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtNewBalance);
			
			gtUint256 gtCurrentReimbursement = LibAccount.initializePartyAReimbursement(partyA);
			gtUint256 gtNewReimbursement = gtCurrentReimbursement.checkedAdd(gtAvailableBalanceAmount);
			accountLayout.encryptedPartyAReimbursement[partyA] = MpcCore.offBoardCombined(gtNewReimbursement, LibAccount.getUserEncryptionAddress(partyA));
			accountLayout.observerEncryptedPartyAReimbursement[partyA] = LibEncryption.offBoardToObserver(gtNewReimbursement);
		}

		maLayout.liquidationStatus[partyA] = true;
		accountLayout.liquidationDetails[partyA] = LiquidationDetail({
			liquidationId: liquidationSig.liquidationId,
			liquidationType: LiquidationType.NONE,
			upnl: liquidationSig.upnl,
			totalUnrealizedLoss: liquidationSig.totalUnrealizedLoss,
			deficit: 0,
			liquidationFee: 0,
			timestamp: liquidationSig.timestamp,
			involvedPartyBCounts: 0,
			partyAAccumulatedUpnl: 0,
			disputed: false,
			liquidationTimestamp: liquidationSig.liquidationTimestamp
		});
		accountLayout.settlementStates[partyA][address(0)].actualAmount = MpcCore.offBoardCombined(
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
			accountLayout.symbolsPrices[partyA][liquidationSig.symbolIds[index]] = Price(liquidationSig.prices[index], detail.timestamp);
		}

		gtInt256 gtAvailableBalance2 = LibAccount.partyAAvailableBalanceForLiquidation(
			liquidationSig.upnl,
			partyA
		);
		if (detail.liquidationType == LiquidationType.NONE) {
			gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].lf.ciphertext);
			gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
			gtUint256 gtDeficitMagnitude = MpcCore.setPublic256(int256(0)).sub(gtAvailableBalance2).fromSigned();
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
