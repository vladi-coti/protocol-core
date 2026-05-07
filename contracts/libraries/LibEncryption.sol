// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../storages/AccountStorage.sol";
import "../storages/QuoteStorage.sol";
import "./LibLockedValues.sol";

library LibEncryption {
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function getUserEncryptionAddress(address user) internal view returns (address) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address userEncryptionAddress = accountLayout.userEncryptionAddress[user];
		return userEncryptionAddress == address(0) ? user : userEncryptionAddress;
	}

	function getObserverEncryptionAddress() internal view returns (address) {
		return AccountStorage.layout().trustedObserverAddress;
	}

	function offBoardToUser(gtUint256 value, address user) internal returns (utUint256 memory) {
		return MpcCore.offBoardCombined(value, getUserEncryptionAddress(user));
	}

	function offBoardToUser(gtInt256 value, address user) internal returns (utInt256 memory) {
		return MpcCore.offBoardCombined(value, getUserEncryptionAddress(user));
	}

	function offBoardToObserver(gtUint256 value) internal returns (ctUint256 memory) {
		address observer = getObserverEncryptionAddress();
		if (observer == address(0)) {
			return ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) });
		}
		return MpcCore.offBoardToUser(value, observer);
	}

	function offBoardToObserver(gtInt256 value) internal returns (ctInt256 memory) {
		address observer = getObserverEncryptionAddress();
		if (observer == address(0)) {
			return ctInt256({ ciphertextHigh: ctInt128.wrap(0), ciphertextLow: ctInt128.wrap(0) });
		}
		return MpcCore.offBoardToUser(value, observer);
	}

	function offBoardLockedToObserver(GarbledLockedValues memory values) internal returns (UserLockedValues memory) {
		address observer = getObserverEncryptionAddress();
		if (observer == address(0)) {
			return UserLockedValues({
				cva: emptyUint256(),
				lf: emptyUint256(),
				partyAmm: emptyUint256(),
				partyBmm: emptyUint256()
			});
		}
		return UserLockedValues({
			cva: MpcCore.offBoardToUser(values.cva, observer),
			lf: MpcCore.offBoardToUser(values.lf, observer),
			partyAmm: MpcCore.offBoardToUser(values.partyAmm, observer),
			partyBmm: MpcCore.offBoardToUser(values.partyBmm, observer)
		});
	}

	function storeUintForAddress(utUint256 storage userValue, ctUint256 storage observerValue, gtUint256 value, address encryptionAddress) internal {
		_assign(userValue, MpcCore.offBoardCombined(value, encryptionAddress));
		_assign(observerValue, offBoardToObserver(value));
	}

	function storeIntForAddress(utInt256 storage userValue, ctInt256 storage observerValue, gtInt256 value, address encryptionAddress) internal {
		_assign(userValue, MpcCore.offBoardCombined(value, encryptionAddress));
		_assign(observerValue, offBoardToObserver(value));
	}

	function storeLockedForAddress(
		LockedValues storage userValue,
		UserLockedValues storage observerValue,
		GarbledLockedValues memory value,
		address encryptionAddress
	) internal {
		_assign(userValue, value.offBoard(encryptionAddress));
		_assign(observerValue, offBoardLockedToObserver(value));
	}

	function storePartyAAllocatedBalance(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) internal {
		accountLayout.allocatedBalances[partyA] = offBoardToUser(value, partyA);
		accountLayout.observerAllocatedBalances[partyA] = offBoardToObserver(value);
	}

	function storePartyBAllocatedBalance(AccountStorage.Layout storage accountLayout, address partyB, address partyA, gtUint256 value) internal {
		accountLayout.partyBAllocatedBalances[partyB][partyA] = offBoardToUser(value, partyB);
		accountLayout.observerPartyBAllocatedBalances[partyB][partyA] = offBoardToObserver(value);
	}

	function storeReserveVault(AccountStorage.Layout storage accountLayout, address partyB, gtUint256 value) internal {
		accountLayout.encryptedReserveVault[partyB] = offBoardToUser(value, partyB);
		accountLayout.observerEncryptedReserveVault[partyB] = offBoardToObserver(value);
	}

	function storeFeeCollectorBalance(AccountStorage.Layout storage accountLayout, address feeCollector, gtUint256 value) internal {
		accountLayout.encryptedFeeCollectorBalances[feeCollector] = offBoardToUser(value, feeCollector);
		accountLayout.observerEncryptedFeeCollectorBalances[feeCollector] = offBoardToObserver(value);
	}

	function storePartyAReimbursement(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) internal {
		accountLayout.encryptedPartyAReimbursement[partyA] = offBoardToUser(value, partyA);
		accountLayout.observerEncryptedPartyAReimbursement[partyA] = offBoardToObserver(value);
	}

	function storeLiquidationDeficit(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) internal {
		accountLayout.encryptedLiquidationDeficit[partyA] = offBoardToUser(value, partyA);
		accountLayout.observerEncryptedLiquidationDeficit[partyA] = offBoardToObserver(value);
	}

	function storeLiquidationFee(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) internal {
		accountLayout.encryptedLiquidationFee[partyA] = offBoardToUser(value, partyA);
		accountLayout.observerEncryptedLiquidationFee[partyA] = offBoardToObserver(value);
	}

	function storePartyALockedBalance(AccountStorage.Layout storage accountLayout, address partyA, GarbledLockedValues memory value) internal {
		storeLockedForAddress(accountLayout.lockedBalances[partyA], accountLayout.observerLockedBalances[partyA], value, getUserEncryptionAddress(partyA));
	}

	function storePartyAPendingLockedBalance(AccountStorage.Layout storage accountLayout, address partyA, GarbledLockedValues memory value) internal {
		storeLockedForAddress(
			accountLayout.pendingLockedBalances[partyA],
			accountLayout.observerPendingLockedBalances[partyA],
			value,
			getUserEncryptionAddress(partyA)
		);
	}

	function storePartyBLockedBalance(
		AccountStorage.Layout storage accountLayout,
		address partyB,
		address partyA,
		GarbledLockedValues memory value
	) internal {
		storeLockedForAddress(
			accountLayout.partyBLockedBalances[partyB][partyA],
			accountLayout.observerPartyBLockedBalances[partyB][partyA],
			value,
			getUserEncryptionAddress(partyB)
		);
	}

	function storePartyBPendingLockedBalance(
		AccountStorage.Layout storage accountLayout,
		address partyB,
		address partyA,
		GarbledLockedValues memory value
	) internal {
		storeLockedForAddress(
			accountLayout.partyBPendingLockedBalances[partyB][partyA],
			accountLayout.observerPartyBPendingLockedBalances[partyB][partyA],
			value,
			getUserEncryptionAddress(partyB)
		);
	}

	function storeQuoteOpenedPrice(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(quote.openedPrice, quoteLayout.observerQuoteValues[quote.id].openedPrice, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteInitialOpenedPrice(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(
			quote.initialOpenedPrice,
			quoteLayout.observerQuoteValues[quote.id].initialOpenedPrice,
			value,
			getUserEncryptionAddress(quote.partyA)
		);
	}

	function storeQuoteRequestedOpenPrice(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(
			quote.requestedOpenPrice,
			quoteLayout.observerQuoteValues[quote.id].requestedOpenPrice,
			value,
			getUserEncryptionAddress(quote.partyA)
		);
	}

	function storeQuoteMarketPrice(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(quote.marketPrice, quoteLayout.observerQuoteValues[quote.id].marketPrice, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteQuantity(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(quote.quantity, quoteLayout.observerQuoteValues[quote.id].quantity, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteClosedAmount(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(quote.closedAmount, quoteLayout.observerQuoteValues[quote.id].closedAmount, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteAvgClosedPrice(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(quote.avgClosedPrice, quoteLayout.observerQuoteValues[quote.id].avgClosedPrice, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteRequestedClosePrice(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(
			quote.requestedClosePrice,
			quoteLayout.observerQuoteValues[quote.id].requestedClosePrice,
			value,
			getUserEncryptionAddress(quote.partyA)
		);
	}

	function storeQuoteQuantityToClose(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(
			quote.quantityToClose,
			quoteLayout.observerQuoteValues[quote.id].quantityToClose,
			value,
			getUserEncryptionAddress(quote.partyA)
		);
	}

	function storeQuoteTradingFee(QuoteStorage.Layout storage quoteLayout, Quote storage quote, gtUint256 value) internal {
		storeUintForAddress(quote.tradingFee, quoteLayout.observerQuoteValues[quote.id].tradingFee, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteLockedValues(QuoteStorage.Layout storage quoteLayout, Quote storage quote, GarbledLockedValues memory value) internal {
		storeLockedForAddress(quote.lockedValues, quoteLayout.observerQuoteValues[quote.id].lockedValues, value, getUserEncryptionAddress(quote.partyA));
	}

	function storeQuoteInitialLockedValues(QuoteStorage.Layout storage quoteLayout, Quote storage quote, GarbledLockedValues memory value) internal {
		storeLockedForAddress(
			quote.initialLockedValues,
			quoteLayout.observerQuoteValues[quote.id].initialLockedValues,
			value,
			getUserEncryptionAddress(quote.partyA)
		);
	}

	function refreshQuoteObserverValues(QuoteStorage.Layout storage quoteLayout, Quote storage quote) internal {
		ObserverQuoteValues storage observerValues = quoteLayout.observerQuoteValues[quote.id];
		observerValues.openedPrice = offBoardToObserver(LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext));
		observerValues.initialOpenedPrice = offBoardToObserver(LockedValuesOps.safeOnboard(quote.initialOpenedPrice.ciphertext));
		observerValues.requestedOpenPrice = offBoardToObserver(LockedValuesOps.safeOnboard(quote.requestedOpenPrice.ciphertext));
		observerValues.marketPrice = offBoardToObserver(LockedValuesOps.safeOnboard(quote.marketPrice.ciphertext));
		observerValues.quantity = offBoardToObserver(LockedValuesOps.safeOnboard(quote.quantity.ciphertext));
		observerValues.closedAmount = offBoardToObserver(LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext));
		observerValues.avgClosedPrice = offBoardToObserver(LockedValuesOps.safeOnboard(quote.avgClosedPrice.ciphertext));
		observerValues.requestedClosePrice = offBoardToObserver(LockedValuesOps.safeOnboard(quote.requestedClosePrice.ciphertext));
		observerValues.quantityToClose = offBoardToObserver(LockedValuesOps.safeOnboard(quote.quantityToClose.ciphertext));
		observerValues.tradingFee = offBoardToObserver(LockedValuesOps.safeOnboard(quote.tradingFee.ciphertext));
		observerValues.initialLockedValues = offBoardLockedToObserver(quote.initialLockedValues.onBoard());
		observerValues.lockedValues = offBoardLockedToObserver(quote.lockedValues.onBoard());
	}

	function storeSettlementCva(
		AccountStorage.Layout storage accountLayout,
		address partyA,
		address partyB,
		gtUint256 value
	) internal {
		storeUintForAddress(
			accountLayout.settlementStates[partyA][partyB].cva,
			accountLayout.observerSettlementStates[partyA][partyB].cva,
			value,
			getUserEncryptionAddress(partyA)
		);
		accountLayout.partyBSettlementStates[partyA][partyB].cva = MpcCore.offBoardToUser(value, getUserEncryptionAddress(partyB));
	}

	function storeSettlementActual(
		AccountStorage.Layout storage accountLayout,
		address partyA,
		address partyB,
		gtInt256 value
	) internal {
		storeIntForAddress(
			accountLayout.settlementStates[partyA][partyB].actualAmount,
			accountLayout.observerSettlementStates[partyA][partyB].actualAmount,
			value,
			getUserEncryptionAddress(partyA)
		);
		accountLayout.partyBSettlementStates[partyA][partyB].actualAmount = MpcCore.offBoardToUser(value, getUserEncryptionAddress(partyB));
	}

	function storeSettlementExpected(
		AccountStorage.Layout storage accountLayout,
		address partyA,
		address partyB,
		gtInt256 value
	) internal {
		storeIntForAddress(
			accountLayout.settlementStates[partyA][partyB].expectedAmount,
			accountLayout.observerSettlementStates[partyA][partyB].expectedAmount,
			value,
			getUserEncryptionAddress(partyA)
		);
		accountLayout.partyBSettlementStates[partyA][partyB].expectedAmount = MpcCore.offBoardToUser(value, getUserEncryptionAddress(partyB));
	}

	function storePartyBSettlementCva(
		AccountStorage.Layout storage accountLayout,
		address partyA,
		address partyB,
		gtUint256 value,
		address encryptionAddress
	) internal {
		_assign(accountLayout.partyBSettlementStates[partyA][partyB].cva, MpcCore.offBoardToUser(value, encryptionAddress));
	}

	function storePartyBSettlementActual(
		AccountStorage.Layout storage accountLayout,
		address partyA,
		address partyB,
		gtInt256 value,
		address encryptionAddress
	) internal {
		_assign(accountLayout.partyBSettlementStates[partyA][partyB].actualAmount, MpcCore.offBoardToUser(value, encryptionAddress));
	}

	function storePartyBSettlementExpected(
		AccountStorage.Layout storage accountLayout,
		address partyA,
		address partyB,
		gtInt256 value,
		address encryptionAddress
	) internal {
		_assign(accountLayout.partyBSettlementStates[partyA][partyB].expectedAmount, MpcCore.offBoardToUser(value, encryptionAddress));
	}

	function emptyUint256() internal pure returns (ctUint256 memory) {
		return ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) });
	}

	function _assign(utUint256 storage target, utUint256 memory value) private {
		target.ciphertext = value.ciphertext;
		target.userCiphertext = value.userCiphertext;
	}

	function _assign(utInt256 storage target, utInt256 memory value) private {
		target.ciphertext = value.ciphertext;
		target.userCiphertext = value.userCiphertext;
	}

	function _assign(ctUint256 storage target, ctUint256 memory value) private {
		target.ciphertextHigh = value.ciphertextHigh;
		target.ciphertextLow = value.ciphertextLow;
	}

	function _assign(ctInt256 storage target, ctInt256 memory value) private {
		target.ciphertextHigh = value.ciphertextHigh;
		target.ciphertextLow = value.ciphertextLow;
	}

	function _assign(LockedValues storage target, LockedValues memory value) private {
		_assign(target.cva, value.cva);
		_assign(target.lf, value.lf);
		_assign(target.partyAmm, value.partyAmm);
		_assign(target.partyBmm, value.partyBmm);
	}

	function _assign(UserLockedValues storage target, UserLockedValues memory value) private {
		_assign(target.cva, value.cva);
		_assign(target.lf, value.lf);
		_assign(target.partyAmm, value.partyAmm);
		_assign(target.partyBmm, value.partyBmm);
	}
}
