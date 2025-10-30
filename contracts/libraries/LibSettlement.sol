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

		int256[] memory settleAmounts = new int256[](settleSig.upnlPartyBs.length);
		address[] memory partyBs = new address[](settleSig.upnlPartyBs.length);
		newPartyBsAllocatedBalances = new utUint256[](settleSig.upnlPartyBs.length);

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

			// Decrypt openedPrice for comparisons (prices from signatures are public)
			gtUint256 gtOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
			uint256 openedPrice = MpcCore.decrypt(gtOpenedPrice);
			
			if (openedPrice > data.currentPrice) {
				require(
					updatedPrices[i] < openedPrice && updatedPrices[i] >= data.currentPrice,
					"LibSettlement: Updated price is out of range"
				);
			} else {
				require(
					updatedPrices[i] > openedPrice && updatedPrices[i] <= data.currentPrice,
					"LibSettlement: Updated price is out of range"
				);
			}
			
			// Calculate settlement amount with encrypted quoteOpenAmount
			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			int256 quoteOpenAmount = int256(MpcCore.decrypt(gtQuoteOpenAmount));
			
			if (quote.positionType == PositionType.LONG) {
				settleAmounts[data.partyBUpnlIndex] +=
					((int256(updatedPrices[i]) - int256(openedPrice)) * quoteOpenAmount) / 1e18;
			} else {
				settleAmounts[data.partyBUpnlIndex] +=
					((int256(openedPrice) - int256(updatedPrices[i])) * quoteOpenAmount) / 1e18;
			}
			
			// Update openedPrice with new encrypted value
			gtUint256 gtUpdatedPrice = MpcCore.setPublic256(updatedPrices[i]);
			quote.openedPrice = MpcCore.offBoardCombined(gtUpdatedPrice, LibAccount.getUserEncryptionAddress(quote.partyA));
		}

		int256 totalSettlementAmount;
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

			int256 settlementAmount = settleAmounts[i];
			totalSettlementAmount += settlementAmount;
			if (settlementAmount >= 0) {
				// Update PartyB balance with encrypted operations
				gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
				gtUint256 gtAmount = MpcCore.setPublic256(uint256(settlementAmount));
				gtUint256 gtNewBalance = gtPartyBBalance.sub(gtAmount);
				accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
				
				// Emit encrypted event
				address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
				ctUint256 memory partyBAmount = MpcCore.offBoardToUser(gtAmount, partyAEncryptionAddress);
				emit SharedEvents.BalanceChangePartyB(partyB, partyA, partyBAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
			} else {
				// Update PartyB balance with encrypted operations
				gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
				gtUint256 gtAmount = MpcCore.setPublic256(uint256(-settlementAmount));
				gtUint256 gtNewBalance = gtPartyBBalance.add(gtAmount);
				accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
				
				// Emit encrypted event
				address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
				ctUint256 memory partyBAmount = MpcCore.offBoardToUser(gtAmount, partyAEncryptionAddress);
				emit SharedEvents.BalanceChangePartyB(partyB, partyA, partyBAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
			}
			// Store the new encrypted balance for return
			newPartyBsAllocatedBalances[i] = accountLayout.partyBAllocatedBalances[partyB][partyA];
		}
		if (totalSettlementAmount >= 0) {
			// Update PartyA balance with encrypted operations
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAmount = MpcCore.setPublic256(uint256(totalSettlementAmount));
			gtUint256 gtNewBalance = gtPartyABalance.add(gtAmount);
			accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
			
			// Emit encrypted event
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtAmount, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(partyA, partyAAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
		} else {
			// Update PartyA balance with encrypted operations
			gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
			gtUint256 gtAmount = MpcCore.setPublic256(uint256(-totalSettlementAmount));
			gtUint256 gtNewBalance = gtPartyABalance.sub(gtAmount);
			accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(partyA));
			
			// Emit encrypted event
			address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
			ctUint256 memory partyAAmount = MpcCore.offBoardToUser(gtAmount, partyAEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(partyA, partyAAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
		}
	}
}
