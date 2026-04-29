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
import "./LibEncryption.sol";

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
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(upnlPartyB, partyB, partyA);
		_liquidatePartyBFromAvailable(partyB, partyA, gtAvailableBalance, timestamp);
	}

	function liquidatePartyBFromAvailable(address partyB, address partyA, gtInt256 gtAvailableBalance, uint256 timestamp) internal {
		_liquidatePartyBFromAvailable(partyB, partyA, gtAvailableBalance, timestamp);
	}

	function _liquidatePartyBFromAvailable(address partyB, address partyA, gtInt256 gtAvailableBalance, uint256 timestamp) private {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
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
				accountLayout.pendingLockedBalances[partyA].subQuote(quote, partyAEncryptionAddress);
				
				// Get encrypted trading fee and update balance with encrypted operations
				gtUint256 gtFee = LibQuote.getTradingFee(quote.id);
				
				// Update PartyA balance with encrypted operations
				gtUint256 gtPartyABalanceFee = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
				gtUint256 gtNewBalance = gtPartyABalanceFee.checkedAdd(gtFee);
				LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtNewBalance);
				
				// Emit encrypted event
				ctUint256 memory ctFee = MpcCore.offBoardToUser(gtFee, partyAEncryptionAddress);
				emit SharedEvents.BalanceChangePartyA(partyA, ctFee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
				
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
		gtUint256 gtValue = gtPartyBBalance.checkedSub(gtRemainingLf);
		
		// Update PartyA balance
		gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
		gtUint256 gtNewPartyABalance = gtPartyABalance.checkedAdd(gtValue);
		LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtNewPartyABalance);
		
		// Emit encrypted event for PartyA
		ctUint256 memory ctValue = MpcCore.offBoardToUser(gtValue, partyAEncryptionAddress);
		emit SharedEvents.BalanceChangePartyA(partyA, ctValue, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);

		// Clear pending quotes and reset balances for Party B
		delete quoteLayout.partyBPendingQuotes[partyB][partyA];
		
		// Emit encrypted event for PartyB
		ctUint256 memory ctPartyBBalance = MpcCore.offBoardToUser(gtPartyBBalance, partyBEncryptionAddress);
		emit SharedEvents.BalanceChangePartyB(
			partyB,
			partyA,
			ctPartyBBalance,
			SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
		);
		
		// Reset PartyB balance to zero
		LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, MpcCore.setPublic256(uint256(0)));
		
		// Set locked balances to zero (encrypted)
		GarbledLockedValues memory gtZeroLocked = LockedValuesOps.makeZero();
		accountLayout.partyBLockedBalances[partyB][partyA] = gtZeroLocked.offBoard(partyBEncryptionAddress);
		accountLayout.partyBPendingLockedBalances[partyB][partyA] = gtZeroLocked.offBoard(partyBEncryptionAddress);
		accountLayout.observerPartyBLockedBalances[partyB][partyA] = LibEncryption.offBoardLockedToObserver(gtZeroLocked);
		accountLayout.observerPartyBPendingLockedBalances[partyB][partyA] = LibEncryption.offBoardLockedToObserver(gtZeroLocked);
		
		accountLayout.partyANonces[partyA] += 1;

		// Transfer liquidator share to the liquidator
		if (liquidatorShare > 0) {
			address liquidatorEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
			// Update liquidator balance with encrypted operations
			gtUint256 gtLiquidatorBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[msg.sender].ciphertext);
			gtUint256 gtLiquidatorShare = MpcCore.setPublic256(liquidatorShare);
			gtUint256 gtNewLiquidatorBalance = gtLiquidatorBalance.checkedAdd(gtLiquidatorShare);
			LibEncryption.storePartyAAllocatedBalance(accountLayout, msg.sender, gtNewLiquidatorBalance);
			
			// Emit encrypted event
			ctUint256 memory ctLiquidatorShare = MpcCore.offBoardToUser(gtLiquidatorShare, liquidatorEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(msg.sender, ctLiquidatorShare, SharedEvents.BalanceChangeType.LF_IN);
		}
	}
}
