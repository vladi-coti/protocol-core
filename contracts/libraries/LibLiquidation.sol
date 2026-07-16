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
	 * @param gtUpnlPartyB The unrealized profit and loss of Party B (encrypted).
	 * @param timestamp The timestamp of the liquidation.
	 */
	function liquidatePartyB(address partyB, address partyA, gtInt256 gtUpnlPartyB, uint256 timestamp) internal {
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableBalanceForLiquidation(gtUpnlPartyB, partyB, partyA);
		_liquidatePartyBFromAvailable(partyB, partyA, gtAvailableBalance, timestamp, msg.sender);
	}

	function liquidatePartyBFromAvailable(
		address partyB,
		address partyA,
		gtInt256 gtAvailableBalance,
		uint256 timestamp,
		address liquidator
	) internal {
		_liquidatePartyBFromAvailable(partyB, partyA, gtAvailableBalance, timestamp, liquidator);
	}

	function _liquidatePartyBFromAvailable(
		address partyB,
		address partyA,
		gtInt256 gtAvailableBalance,
		uint256 timestamp,
		address liquidator
	) private {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
		gtInt256 gtZero = MpcCore.setPublic256(int256(0));

		// Ensure Party B is insolvent (decrypt for comparison)
		require(MpcCore.decrypt(gtAvailableBalance.lt(gtZero)), "LiquidationFacet: partyB is solvent");
		
		gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.partyBLockedBalances[partyB][partyA].lf.ciphertext);
		gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
		gtUint256 gtDeficitMagnitude = gtZero.checkedSub(gtAvailableBalance).fromSigned();
		gtUint256 gtRemainingLf = MpcCore.setPublic256(uint256(0));
		gtUint256 gtLiquidatorShare = MpcCore.setPublic256(uint256(0));
		gtUint256 gtPerPositionShare = MpcCore.setPublic256(uint256(0));
		
		if (MpcCore.decrypt(gtDeficitMagnitude.lt(gtLf))) {
			gtRemainingLf = gtLf.checkedSub(gtDeficitMagnitude);
			// Positive UPNL can make remainingLf > allocated; cap to payable balance (H-15).
			gtRemainingLf = MpcCore.min(gtRemainingLf, gtPartyBBalance);
			gtLiquidatorShare = gtRemainingLf.checkedMul(MpcCore.setPublic256(maLayout.liquidatorShare)).div(MpcCore.setPublic256(uint256(1e18)));
			gtPerPositionShare = gtRemainingLf.checkedSub(gtLiquidatorShare).div(MpcCore.setPublic256(quoteLayout.partyBPositionsCount[partyB][partyA]));
		}
		maLayout.encryptedPartyBPositionLiquidatorsShare[partyB][partyA] = MpcCore.offBoard(gtPerPositionShare);
		maLayout.partyBPositionLiquidatorsShare[partyB][partyA] = 0;

		// Update liquidation status and timestamp for Party B
		maLayout.partyBLiquidationStatus[partyB][partyA] = true;
		maLayout.partyBLiquidationTimestamp[partyB][partyA] = timestamp;

		uint256[] storage pendingQuotes = quoteLayout.partyAPendingQuotes[partyA];

		for (uint256 index = 0; index < pendingQuotes.length; ) {
			Quote storage quote = quoteLayout.quotes[pendingQuotes[index]];
			if (quote.partyB == partyB && (quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING)) {
				LibEncryption.storePartyAPendingLockedBalance(accountLayout, partyA, accountLayout.pendingLockedBalances[partyA].subQuoteGarbled(quote));
				
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
		LibEncryption.storePartyBLockedBalance(accountLayout, partyB, partyA, gtZeroLocked);
		LibEncryption.storePartyBPendingLockedBalance(accountLayout, partyB, partyA, gtZeroLocked);
		
		accountLayout.partyANonces[partyA] += 1;

		// Transfer liquidator share to the designated liquidator (not necessarily msg.sender).
		if (MpcCore.decrypt(gtLiquidatorShare.gt(MpcCore.setPublic256(uint256(0))))) {
			LibAccount.initializePartyA(liquidator);
			address liquidatorEncryptionAddress = LibAccount.getUserEncryptionAddress(liquidator);
			gtUint256 gtLiquidatorBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[liquidator].ciphertext);
			gtUint256 gtNewLiquidatorBalance = gtLiquidatorBalance.checkedAdd(gtLiquidatorShare);
			LibEncryption.storePartyAAllocatedBalance(accountLayout, liquidator, gtNewLiquidatorBalance);

			ctUint256 memory ctLiquidatorShare = MpcCore.offBoardToUser(gtLiquidatorShare, liquidatorEncryptionAddress);
			emit SharedEvents.BalanceChangePartyA(liquidator, ctLiquidatorShare, SharedEvents.BalanceChangeType.LF_IN);
		}
	}
}
