// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/MAStorage.sol";
import "../storages/MuonStorage.sol";
import "../storages/AccountStorage.sol";
import "./LibQuote.sol";
import "./LibAccount.sol";

library LibSettlement {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function settleUpnl(
		SettlementSig memory settleSig,
		uint256[] memory updatedPrices,
		address partyA,
		bool isForceClose
	) internal returns (utUint256[] memory newPartyBsAllocatedBalances) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(settleSig.quotesSettlementsData.length > 0 && settleSig.quotesSettlementsData.length == updatedPrices.length, "LibSettlement: Invalid length");
		
		// Check PartyA solvency using encrypted balance calculation
		gtInt256 gtPartyAAvailable = LibAccount.partyAAvailableBalanceForLiquidation(settleSig.upnlPartyA, partyA);
		gtInt256 gtZeroInt = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtPartyAAvailable.ge(gtZeroInt)), "LibSettlement: PartyA is insolvent");

		require(
			isForceClose || quoteLayout.partyBOpenPositions[msg.sender][partyA].length > 0,
			"LibSettlement: Sender should have a position with partyA"
		);
		accountLayout.partyANonces[partyA] += 1;

		gtInt256[] memory gtSettleAmounts = new gtInt256[](settleSig.upnlPartyBs.length);
		address[] memory partyBs = new address[](settleSig.upnlPartyBs.length);
		newPartyBsAllocatedBalances = new utUint256[](settleSig.upnlPartyBs.length);
		for (uint8 i = 0; i < gtSettleAmounts.length; i++) {
			gtSettleAmounts[i] = gtZeroInt;
		}

		for (uint8 i = 0; i < settleSig.quotesSettlementsData.length; i++) {
			QuoteSettlementData memory data = settleSig.quotesSettlementsData[i];
			Quote storage quote = quoteLayout.quotes[data.quoteId];
			require(quote.partyA == partyA, "LibSettlement: PartyA is invalid");
			require(
				quote.quoteStatus == QuoteStatus.OPENED ||
					quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
					quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
				"LibSettlement: Invalid state"
			);
			require(data.partyBUpnlIndex <= settleSig.upnlPartyBs.length, "LibSettlement: Invalid partyBUpnlIndex in signature");
			require(
				partyBs[data.partyBUpnlIndex] == address(0) || partyBs[data.partyBUpnlIndex] == quote.partyB,
				"LibSettlement: Invalid upnlPartyBs list"
			);
			partyBs[data.partyBUpnlIndex] = quote.partyB;

			gtUint256 gtOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
			gtUint256 gtCurrentPrice = MpcCore.setPublic256(data.currentPrice);
			gtUint256 gtUpdatedPrice = MpcCore.setPublic256(updatedPrices[i]);
			gtBool gtOpenedGtCurrent = gtOpenedPrice.gt(gtCurrentPrice);
			gtBool gtUpdatedLtOpened = gtUpdatedPrice.lt(gtOpenedPrice);
			gtBool gtUpdatedGtOpened = gtUpdatedPrice.gt(gtOpenedPrice);

			gtBool gtValidDownMove = gtUpdatedLtOpened.and(gtUpdatedPrice.ge(gtCurrentPrice));
			gtBool gtValidUpMove = gtUpdatedGtOpened.and(gtUpdatedPrice.le(gtCurrentPrice));
			gtBool gtValidUpdatedPrice = MpcCore.mux(gtOpenedGtCurrent, gtValidUpMove, gtValidDownMove);
			require(MpcCore.decrypt(gtValidUpdatedPrice), "LibSettlement: Updated price is out of range");

			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			gtUint256 gtPriceDiff = MpcCore.max(gtUpdatedPrice, gtOpenedPrice).sub(MpcCore.min(gtUpdatedPrice, gtOpenedPrice));
			gtInt256 gtImpact = gtQuoteOpenAmount.mul(gtPriceDiff).div(MpcCore.setPublic256(uint256(1e18))).toSigned();
			gtInt256 gtSignedImpact;

			if (quote.positionType == PositionType.LONG) {
				gtSignedImpact = MpcCore.mux(gtUpdatedGtOpened, gtZeroInt.sub(gtImpact), gtImpact);
			} else {
				gtSignedImpact = MpcCore.mux(gtUpdatedGtOpened, gtImpact, gtZeroInt.sub(gtImpact));
			}
			gtSettleAmounts[data.partyBUpnlIndex] = gtSettleAmounts[data.partyBUpnlIndex].add(gtSignedImpact);

			quote.openedPrice = MpcCore.offBoardCombined(gtUpdatedPrice, LibAccount.getUserEncryptionAddress(quote.partyA));
		}

		gtInt256 gtTotalSettlementAmount = gtZeroInt;
		for (uint8 i = 0; i < partyBs.length; i++) {
			address partyB = partyBs[i];
			
			// Check PartyB solvency using encrypted balance calculation
			gtInt256 gtPartyBAvailable = LibAccount.partyBAvailableBalanceForLiquidation(settleSig.upnlPartyBs[i], partyB, partyA);
			require(MpcCore.decrypt(gtPartyBAvailable.ge(gtZeroInt)), "LibSettlement: PartyB should be solvent");
			
			require(!MAStorage.layout().partyBLiquidationStatus[partyB][partyA], "LibSettlement: PartyB is in liquidation process");

			if (!isForceClose && msg.sender != partyB) {
				require(
					block.timestamp >=
						MAStorage.layout().lastUpnlSettlementTimestamp[msg.sender][partyB][partyA] + MAStorage.layout().settlementCooldown,
					"LibSettlement: Cooldown should be passed"
				);
				MAStorage.layout().lastUpnlSettlementTimestamp[msg.sender][partyB][partyA] = block.timestamp;
			}
			accountLayout.partyBNonces[partyB][partyA] += 1;

			gtInt256 gtSettlementAmount = gtSettleAmounts[i];
			gtTotalSettlementAmount = gtTotalSettlementAmount.add(gtSettlementAmount);
			if (MpcCore.decrypt(gtSettlementAmount.ge(gtZeroInt))) {
				// Update PartyB balance with encrypted operations
				gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
				gtUint256 gtAmount = gtSettlementAmount.fromSigned();
				gtUint256 gtNewBalance = gtPartyBBalance.sub(gtAmount);
				accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyB));
				
				// Emit encrypted event
				address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
				ctUint256 memory partyBAmount = MpcCore.offBoardToUser(gtAmount, partyBEncryptionAddress);
				emit SharedEvents.BalanceChangePartyB(partyB, partyA, partyBAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
			} else {
				// Update PartyB balance with encrypted operations
				gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
				gtUint256 gtAmount = gtZeroInt.sub(gtSettlementAmount).fromSigned();
				gtUint256 gtNewBalance = gtPartyBBalance.add(gtAmount);
				accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyB));
				
				// Emit encrypted event
				address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
				ctUint256 memory partyBAmount = MpcCore.offBoardToUser(gtAmount, partyBEncryptionAddress);
				emit SharedEvents.BalanceChangePartyB(partyB, partyA, partyBAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
			}
			// Store the new encrypted balance for return
			newPartyBsAllocatedBalances[i] = accountLayout.partyBAllocatedBalances[partyB][partyA];
		}
		if (MpcCore.decrypt(gtTotalSettlementAmount.ge(gtZeroInt))) {
			// Update PartyA balance with encrypted operations
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAmount = gtTotalSettlementAmount.fromSigned();
			gtUint256 gtNewBalance = gtPartyABalance.add(gtAmount);
			accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
			
			// Emit encrypted event
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtAmount, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(partyA, partyAAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
		} else {
			// Update PartyA balance with encrypted operations
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAmount = gtZeroInt.sub(gtTotalSettlementAmount).fromSigned();
			gtUint256 gtNewBalance = gtPartyABalance.sub(gtAmount);
			accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
			
			// Emit encrypted event
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtAmount, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(partyA, partyAAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
		}
	}
}
