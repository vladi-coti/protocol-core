// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
pragma solidity >=0.8.18;

import "../storages/AccountStorage.sol";
import "../storages/QuoteStorage.sol";
import "../storages/MAStorage.sol";
import "./LibAccount.sol";
import "./LibEncryption.sol";

library LibAccountEncryption {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function setEncryptionAddress(address user, address newEncryptionAddress) external {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address currentMapped = accountLayout.userEncryptionAddress[user];
		address effectiveCurrent = currentMapped == address(0) ? user : currentMapped;
		require(newEncryptionAddress != address(0), "AccountFacet: zero encryption address");
		require(newEncryptionAddress != effectiveCurrent, "AccountFacet: encryption address unchanged");

		gtUint256 gtValue = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[user].ciphertext);
		accountLayout.allocatedBalances[user] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		accountLayout.observerAllocatedBalances[user] = LibEncryption.offBoardToObserver(gtValue);

		GarbledLockedValues memory gtLocked = accountLayout.lockedBalances[user].onBoard();
		accountLayout.lockedBalances[user] = gtLocked.offBoard(newEncryptionAddress);
		accountLayout.observerLockedBalances[user] = LibEncryption.offBoardLockedToObserver(gtLocked);
		gtLocked = accountLayout.pendingLockedBalances[user].onBoard();
		accountLayout.pendingLockedBalances[user] = gtLocked.offBoard(newEncryptionAddress);
		accountLayout.observerPendingLockedBalances[user] = LibEncryption.offBoardLockedToObserver(gtLocked);

		gtValue = LibAccount.initializeReserveVault(user);
		accountLayout.encryptedReserveVault[user] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		accountLayout.observerEncryptedReserveVault[user] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LibAccount.initializeFeeCollectorBalance(user);
		accountLayout.encryptedFeeCollectorBalances[user] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		accountLayout.observerEncryptedFeeCollectorBalances[user] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LibAccount.initializePartyAReimbursement(user);
		accountLayout.encryptedPartyAReimbursement[user] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		accountLayout.observerEncryptedPartyAReimbursement[user] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(accountLayout.encryptedLiquidationDeficit[user].ciphertext);
		accountLayout.encryptedLiquidationDeficit[user] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		accountLayout.observerEncryptedLiquidationDeficit[user] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(accountLayout.encryptedLiquidationFee[user].ciphertext);
		accountLayout.encryptedLiquidationFee[user] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		accountLayout.observerEncryptedLiquidationFee[user] = LibEncryption.offBoardToObserver(gtValue);

		_reencryptSettlementStateForPartyA(accountLayout, user, address(0), newEncryptionAddress);

		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		uint256[] storage ids = quoteLayout.quoteIdsOf[user];
		for (uint256 i = 0; i < ids.length; i++) {
			Quote storage q = quoteLayout.quotes[ids[i]];
			if (q.partyA != user) continue;
			_reencryptQuoteForPartyA(q, quoteLayout.observerQuoteValues[ids[i]], newEncryptionAddress);
			if (q.partyB != address(0)) {
				_reencryptSettlementStateForPartyA(accountLayout, user, q.partyB, newEncryptionAddress);
			}
		}

		address[] storage partyAs = accountLayout.partyBConnectedPartyAs[user];
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			require(!MAStorage.layout().partyBLiquidationStatus[user][partyA], "Accessibility: PartyB isn't solvent");

			gtValue = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[user][partyA].ciphertext);
			accountLayout.partyBAllocatedBalances[user][partyA] = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
			accountLayout.observerPartyBAllocatedBalances[user][partyA] = LibEncryption.offBoardToObserver(gtValue);

			gtLocked = accountLayout.partyBLockedBalances[user][partyA].onBoard();
			accountLayout.partyBLockedBalances[user][partyA] = gtLocked.offBoard(newEncryptionAddress);
			accountLayout.observerPartyBLockedBalances[user][partyA] = LibEncryption.offBoardLockedToObserver(gtLocked);
			gtLocked = accountLayout.partyBPendingLockedBalances[user][partyA].onBoard();
			accountLayout.partyBPendingLockedBalances[user][partyA] = gtLocked.offBoard(newEncryptionAddress);
			accountLayout.observerPartyBPendingLockedBalances[user][partyA] = LibEncryption.offBoardLockedToObserver(gtLocked);
			_reencryptSettlementStateForPartyB(accountLayout, partyA, user, newEncryptionAddress);
		}

		accountLayout.userEncryptionAddress[user] = newEncryptionAddress;
	}

	function _reencryptQuoteForPartyA(Quote storage q, ObserverQuoteValues storage observerValues, address newEncryptionAddress) private {
		gtUint256 gtValue = LockedValuesOps.safeOnboard(q.openedPrice.ciphertext);
		q.openedPrice = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.openedPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.initialOpenedPrice.ciphertext);
		q.initialOpenedPrice = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.initialOpenedPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.requestedOpenPrice.ciphertext);
		q.requestedOpenPrice = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.requestedOpenPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.marketPrice.ciphertext);
		q.marketPrice = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.marketPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.quantity.ciphertext);
		q.quantity = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.quantity = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.closedAmount.ciphertext);
		q.closedAmount = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.closedAmount = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.avgClosedPrice.ciphertext);
		q.avgClosedPrice = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.avgClosedPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.requestedClosePrice.ciphertext);
		q.requestedClosePrice = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.requestedClosePrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.quantityToClose.ciphertext);
		q.quantityToClose = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.quantityToClose = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.tradingFee.ciphertext);
		q.tradingFee = MpcCore.offBoardCombined(gtValue, newEncryptionAddress);
		observerValues.tradingFee = LibEncryption.offBoardToObserver(gtValue);
		GarbledLockedValues memory gtLocked = q.initialLockedValues.onBoard();
		q.initialLockedValues = gtLocked.offBoard(newEncryptionAddress);
		observerValues.initialLockedValues = LibEncryption.offBoardLockedToObserver(gtLocked);
		gtLocked = q.lockedValues.onBoard();
		q.lockedValues = gtLocked.offBoard(newEncryptionAddress);
		observerValues.lockedValues = LibEncryption.offBoardLockedToObserver(gtLocked);
	}

	function _reencryptSettlementStateForPartyA(AccountStorage.Layout storage accountLayout, address partyA, address partyB, address newEncryptionAddress) private {
		gtInt256 gtActual = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].actualAmount.ciphertext);
		accountLayout.settlementStates[partyA][partyB].actualAmount = MpcCore.offBoardCombined(gtActual, newEncryptionAddress);
		accountLayout.observerSettlementStates[partyA][partyB].actualAmount = LibEncryption.offBoardToObserver(gtActual);
		gtInt256 gtExpected = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].expectedAmount.ciphertext);
		accountLayout.settlementStates[partyA][partyB].expectedAmount = MpcCore.offBoardCombined(gtExpected, newEncryptionAddress);
		accountLayout.observerSettlementStates[partyA][partyB].expectedAmount = LibEncryption.offBoardToObserver(gtExpected);
		gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].cva.ciphertext);
		accountLayout.settlementStates[partyA][partyB].cva = MpcCore.offBoardCombined(gtCva, newEncryptionAddress);
		accountLayout.observerSettlementStates[partyA][partyB].cva = LibEncryption.offBoardToObserver(gtCva);
	}

	function _reencryptSettlementStateForPartyB(AccountStorage.Layout storage accountLayout, address partyA, address partyB, address newEncryptionAddress) private {
		gtInt256 gtActual = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].actualAmount.ciphertext);
		accountLayout.partyBSettlementStates[partyA][partyB].actualAmount = MpcCore.offBoardToUser(gtActual, newEncryptionAddress);
		gtInt256 gtExpected = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].expectedAmount.ciphertext);
		accountLayout.partyBSettlementStates[partyA][partyB].expectedAmount = MpcCore.offBoardToUser(gtExpected, newEncryptionAddress);
		gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].cva.ciphertext);
		accountLayout.partyBSettlementStates[partyA][partyB].cva = MpcCore.offBoardToUser(gtCva, newEncryptionAddress);
	}
}
