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

	/**
	 * @notice Re-offboard PartyA observer ciphertext from primary user storage for the current trustedObserverAddress.
	 * @dev Flip-first rotation catch-up. Header runs when quoteStart == 0. Pages quoteIdsOf[partyA][start:start+limit]
	 *      and migrates active quotes only; PartyB ledgers for counterparties in that page are included.
	 */
	function migrateObserverForPartyA(address partyA, uint256 quoteStart, uint256 quoteLimit) external {
		require(partyA != address(0), "ControlFacet: Zero address");
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

		if (quoteStart == 0) {
			_migrateObserverPartyAHeader(accountLayout, partyA);
		}

		uint256[] storage ids = quoteLayout.quoteIdsOf[partyA];
		uint256 end = quoteStart + quoteLimit;
		if (end > ids.length) {
			end = ids.length;
		}
		for (uint256 i = quoteStart; i < end; i++) {
			Quote storage q = quoteLayout.quotes[ids[i]];
			if (q.partyA != partyA || !_isActiveQuoteStatus(q.quoteStatus)) {
				continue;
			}
			_migrateObserverQuote(q, quoteLayout.observerQuoteValues[ids[i]]);
			if (q.partyB != address(0)) {
				_migrateObserverPartyBForPartyA(accountLayout, partyA, q.partyB);
			}
		}
	}

	/**
	 * @notice Re-offboard PartyB-only observer slots (reserve vault, fee collector) for the current observer.
	 */
	function migrateObserverForPartyBs(address[] calldata partyBs) external {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		for (uint256 i = 0; i < partyBs.length; i++) {
			address partyB = partyBs[i];
			require(partyB != address(0), "ControlFacet: Zero address");
			gtUint256 gtValue = LibAccount.initializeReserveVault(partyB);
			accountLayout.observerEncryptedReserveVault[partyB] = LibEncryption.offBoardToObserver(gtValue);
			gtValue = LibAccount.initializeFeeCollectorBalance(partyB);
			accountLayout.observerEncryptedFeeCollectorBalances[partyB] = LibEncryption.offBoardToObserver(gtValue);
		}
	}

	function _isActiveQuoteStatus(QuoteStatus status) private pure returns (bool) {
		return
			status == QuoteStatus.PENDING ||
			status == QuoteStatus.LOCKED ||
			status == QuoteStatus.CANCEL_PENDING ||
			status == QuoteStatus.OPENED ||
			status == QuoteStatus.CLOSE_PENDING ||
			status == QuoteStatus.CANCEL_CLOSE_PENDING ||
			status == QuoteStatus.LIQUIDATED_PENDING;
	}

	function _migrateObserverPartyAHeader(AccountStorage.Layout storage accountLayout, address partyA) private {
		gtUint256 gtValue = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
		accountLayout.observerAllocatedBalances[partyA] = LibEncryption.offBoardToObserver(gtValue);

		GarbledLockedValues memory gtLocked = accountLayout.lockedBalances[partyA].onBoard();
		accountLayout.observerLockedBalances[partyA] = LibEncryption.offBoardLockedToObserver(gtLocked);
		gtLocked = accountLayout.pendingLockedBalances[partyA].onBoard();
		accountLayout.observerPendingLockedBalances[partyA] = LibEncryption.offBoardLockedToObserver(gtLocked);

		gtValue = LibAccount.initializePartyAReimbursement(partyA);
		accountLayout.observerEncryptedPartyAReimbursement[partyA] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LibAccount.initializeFeeCollectorBalance(partyA);
		accountLayout.observerEncryptedFeeCollectorBalances[partyA] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LibAccount.initializeReserveVault(partyA);
		accountLayout.observerEncryptedReserveVault[partyA] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(accountLayout.encryptedLiquidationDeficit[partyA].ciphertext);
		accountLayout.observerEncryptedLiquidationDeficit[partyA] = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(accountLayout.encryptedLiquidationFee[partyA].ciphertext);
		accountLayout.observerEncryptedLiquidationFee[partyA] = LibEncryption.offBoardToObserver(gtValue);

		_migrateObserverSettlement(accountLayout, partyA, address(0));
	}

	function _migrateObserverPartyBForPartyA(AccountStorage.Layout storage accountLayout, address partyA, address partyB) private {
		gtUint256 gtValue = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
		accountLayout.observerPartyBAllocatedBalances[partyB][partyA] = LibEncryption.offBoardToObserver(gtValue);

		GarbledLockedValues memory gtLocked = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		accountLayout.observerPartyBLockedBalances[partyB][partyA] = LibEncryption.offBoardLockedToObserver(gtLocked);
		gtLocked = accountLayout.partyBPendingLockedBalances[partyB][partyA].onBoard();
		accountLayout.observerPartyBPendingLockedBalances[partyB][partyA] = LibEncryption.offBoardLockedToObserver(gtLocked);

		_migrateObserverSettlement(accountLayout, partyA, partyB);
	}

	function _migrateObserverSettlement(AccountStorage.Layout storage accountLayout, address partyA, address partyB) private {
		gtInt256 gtActual = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].actualAmount.ciphertext);
		accountLayout.observerSettlementStates[partyA][partyB].actualAmount = LibEncryption.offBoardToObserver(gtActual);
		gtInt256 gtExpected = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].expectedAmount.ciphertext);
		accountLayout.observerSettlementStates[partyA][partyB].expectedAmount = LibEncryption.offBoardToObserver(gtExpected);
		gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].cva.ciphertext);
		accountLayout.observerSettlementStates[partyA][partyB].cva = LibEncryption.offBoardToObserver(gtCva);
	}

	function _migrateObserverQuote(Quote storage q, ObserverQuoteValues storage observerValues) private {
		gtUint256 gtValue = LockedValuesOps.safeOnboard(q.openedPrice.ciphertext);
		observerValues.openedPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.initialOpenedPrice.ciphertext);
		observerValues.initialOpenedPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.requestedOpenPrice.ciphertext);
		observerValues.requestedOpenPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.marketPrice.ciphertext);
		observerValues.marketPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.quantity.ciphertext);
		observerValues.quantity = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.closedAmount.ciphertext);
		observerValues.closedAmount = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.avgClosedPrice.ciphertext);
		observerValues.avgClosedPrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.requestedClosePrice.ciphertext);
		observerValues.requestedClosePrice = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.quantityToClose.ciphertext);
		observerValues.quantityToClose = LibEncryption.offBoardToObserver(gtValue);
		gtValue = LockedValuesOps.safeOnboard(q.tradingFee.ciphertext);
		observerValues.tradingFee = LibEncryption.offBoardToObserver(gtValue);
		GarbledLockedValues memory gtLocked = q.initialLockedValues.onBoard();
		observerValues.initialLockedValues = LibEncryption.offBoardLockedToObserver(gtLocked);
		gtLocked = q.lockedValues.onBoard();
		observerValues.lockedValues = LibEncryption.offBoardLockedToObserver(gtLocked);
	}
}
