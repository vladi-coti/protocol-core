// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/MuonStorage.sol";
import "../storages/QuoteStorage.sol";
import "../libraries/SharedEvents.sol";
import "./LibAccount.sol";
import "./LibQuote.sol";

library LibLiquidation {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	/**
	 * @notice Liquidates Party B.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @param upnlPartyB The unrealized profit and loss of Party B (unencrypted).
	 * @param timestamp The timestamp of the liquidation.
	 */
	function liquidatePartyB(address partyB, address partyA, int256 upnlPartyB, uint256 timestamp) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

		// Calculate available balance for liquidation (returns encrypted)
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlPartyB, partyB, partyA);
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));

		// Ensure Party B is insolvent (decrypt for comparison)
		require(MpcCore.decrypt(gtAvailableBalance.lt(gtZero)), "LiquidationFacet: partyB is solvent");
		
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);

		uint256 liquidatorShare;
		uint256 remainingLf;

		// Determine liquidator share and remaining locked funds
		// Decrypt lf for calculation
		gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.partyBLockedBalances[partyB][partyA].lf.ciphertext);
		uint256 lf = MpcCore.decrypt(gtLf);
		
		if (uint256(-availableBalance) < lf) {
			remainingLf = lf - uint256(-availableBalance);
			liquidatorShare = (remainingLf * maLayout.liquidatorShare) / 1e18;

			maLayout.partyBPositionLiquidatorsShare[partyB][partyA] =
				(remainingLf - liquidatorShare) /
				quoteLayout.partyBPositionsCount[partyB][partyA];
		} else {
			maLayout.partyBPositionLiquidatorsShare[partyB][partyA] = 0;
		}

		// Update liquidation status and timestamp for Party B
		maLayout.partyBLiquidationStatus[partyB][partyA] = true;
		maLayout.partyBLiquidationTimestamp[partyB][partyA] = timestamp;

		uint256[] storage pendingQuotes = quoteLayout.partyAPendingQuotes[partyA];

		for (uint256 index = 0; index < pendingQuotes.length; ) {
			Quote storage quote = quoteLayout.quotes[pendingQuotes[index]];
			if (quote.partyB == partyB && (quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING)) {
				accountLayout.pendingLockedBalances[partyA].subQuote(quote);
				
				// Get encrypted trading fee and update balance with encrypted operations
				gtUint256 gtFee = LibQuote.getTradingFee(quote.id);
				uint256 fee = MpcCore.decrypt(gtFee);
				
				// Update PartyA balance with encrypted operations
				gtUint256 gtPartyABalanceFee = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
				gtUint256 gtNewBalance = gtPartyABalanceFee.add(gtFee);
				accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewBalance, partyA);
				
				emit SharedEvents.BalanceChangePartyA(partyA, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
				
				pendingQuotes[index] = pendingQuotes[pendingQuotes.length - 1];
				pendingQuotes.pop();
				quote.quoteStatus = QuoteStatus.LIQUIDATED_PENDING;
				quote.statusModifyTimestamp = block.timestamp;
			} else {
				index++;
			}
		}

		// Update allocated balances for Party A using encrypted operations
		gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
		gtUint256 gtRemainingLf = MpcCore.setPublic256(remainingLf);
		gtUint256 gtValue = gtPartyBBalance.sub(gtRemainingLf);
		uint256 value = MpcCore.decrypt(gtValue);
		
		// Update PartyA balance
		gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
		gtUint256 gtNewPartyABalance = gtPartyABalance.add(gtValue);
		accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtNewPartyABalance, partyA);
		
		emit SharedEvents.BalanceChangePartyA(partyA, value, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);

		// Clear pending quotes and reset balances for Party B
		delete quoteLayout.partyBPendingQuotes[partyB][partyA];
		
		// Decrypt balance for event emission
		uint256 partyBBalance = MpcCore.decrypt(gtPartyBBalance);
		emit SharedEvents.BalanceChangePartyB(
			partyB,
			partyA,
			partyBBalance,
			SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
		);
		
		// Reset PartyB balance to zero
		accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(MpcCore.setPublic256(uint256(0)), partyA);
		
		// Set locked balances to zero (encrypted)
		GarbledLockedValues memory gtZeroLocked = LockedValuesOps.makeZero();
		accountLayout.partyBLockedBalances[partyB][partyA] = gtZeroLocked.offBoard(partyA);
		accountLayout.partyBPendingLockedBalances[partyB][partyA] = gtZeroLocked.offBoard(partyA);
		
		accountLayout.partyANonces[partyA] += 1;

		// Transfer liquidator share to the liquidator
		if (liquidatorShare > 0) {
			// Update liquidator balance with encrypted operations
			gtUint256 gtLiquidatorBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[msg.sender].ciphertext);
			gtUint256 gtLiquidatorShare = MpcCore.setPublic256(liquidatorShare);
			gtUint256 gtNewLiquidatorBalance = gtLiquidatorBalance.add(gtLiquidatorShare);
			accountLayout.allocatedBalances[msg.sender] = MpcCore.offBoardCombined(gtNewLiquidatorBalance, msg.sender);
			
			emit SharedEvents.BalanceChangePartyA(msg.sender, liquidatorShare, SharedEvents.BalanceChangeType.LF_IN);
		}
	}
}
