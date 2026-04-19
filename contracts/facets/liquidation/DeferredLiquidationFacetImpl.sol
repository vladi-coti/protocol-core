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

	function deferredLiquidatePartyA(address partyA, DeferredLiquidationSig memory liquidationSig) internal {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LibMuonLiquidation.verifyDeferredLiquidationSig(liquidationSig, partyA);

		gtInt256 gtLiquidationAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			liquidationSig.upnl,
			liquidationSig.liquidationAllocatedBalance,
			partyA
		);
		int256 liquidationAvailableBalance = MpcCore.decrypt(gtLiquidationAvailableBalance);
		require(liquidationAvailableBalance < 0, "LiquidationFacet: PartyA is solvent");

		gtInt256 gtAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
			liquidationSig.upnl,
			partyA
		);
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
		if (availableBalance > 0) {
			// Update allocated balance with encrypted operations
			gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAvailableBalanceAmount = MpcCore.setPublic256(uint256(availableBalance));
			gtUint256 gtNewBalance = gtCurrentBalance.sub(gtAvailableBalanceAmount);
			accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
			
			accountLayout.partyAReimbursement[partyA] += uint256(availableBalance);
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
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance2);

		if (detail.liquidationType == LiquidationType.NONE) {
			// Decrypt lf and cva for liquidation type determination
			gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].lf.ciphertext);
			gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
			uint256 lf = MpcCore.decrypt(gtLf);
			uint256 cva = MpcCore.decrypt(gtCva);
			
			if (uint256(-availableBalance) < lf) {
				uint256 remainingLf = lf - uint256(-availableBalance);
				detail.liquidationType = LiquidationType.NORMAL;
				detail.liquidationFee = remainingLf;
			} else if (uint256(-availableBalance) <= lf + cva) {
				uint256 deficit = uint256(-availableBalance) - lf;
				detail.liquidationType = LiquidationType.LATE;
				detail.deficit = deficit;
			} else {
				uint256 deficit = uint256(-availableBalance) - lf - cva;
				detail.liquidationType = LiquidationType.OVERDUE;
				detail.deficit = deficit;
			}
			accountLayout.liquidators[partyA].push(msg.sender);
		}
	}
}
