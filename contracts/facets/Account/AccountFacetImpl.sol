// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/GlobalAppStorage.sol";
import "../../storages/MAStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../libraries/muon/LibMuonAccount.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibEncryption.sol";

library AccountFacetImpl {
	using SafeERC20 for IERC20;
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function deposit(address user, uint256 amount) internal {
		GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();
		IERC20(appLayout.collateral).safeTransferFrom(msg.sender, address(this), amount);
		uint256 amountWith18Decimals = (amount * 1e18) / (10 ** IERC20Metadata(appLayout.collateral).decimals());
		AccountStorage.layout().balances[user] += amountWith18Decimals;
	}

	function withdraw(address user, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GlobalAppStorage.Layout storage appLayout = GlobalAppStorage.layout();
		require(
			block.timestamp >= accountLayout.withdrawCooldown[msg.sender] + MAStorage.layout().deallocateCooldown,
			"AccountFacet: Cooldown hasn't reached"
		);
		uint256 amountWith18Decimals = (amount * 1e18) / (10 ** IERC20Metadata(appLayout.collateral).decimals());
		accountLayout.balances[msg.sender] -= amountWith18Decimals;
		IERC20(appLayout.collateral).safeTransfer(user, amount);
	}

	function allocate(uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		
		// Initialize Party A encrypted values to zeros if uninitialized
		LibAccount.initializePartyA(msg.sender);
		
		// Check limit using encrypted comparison
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[msg.sender].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtUint256 gtLimit = MpcCore.setPublic256(GlobalAppStorage.layout().balanceLimitPerUser);
		
		// Check limit using encrypted comparison
		gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtAmount);
		gtBool gtWithinLimit = gtNewBalance.le(gtLimit);
		require(MpcCore.decrypt(gtWithinLimit), "AccountFacet: Allocated balance limit reached");
		
		require(accountLayout.balances[msg.sender] >= amount, "AccountFacet: Insufficient balance");
		accountLayout.balances[msg.sender] -= amount;
		
		// Store encrypted new balance
		_storePartyAAllocatedBalance(accountLayout, msg.sender, gtNewBalance);
	}

	function deallocate(uint256 amount, SingleUpnlSig memory upnlSig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(
			block.timestamp >= accountLayout.withdrawCooldown[msg.sender] + MAStorage.layout().deallocateDebounceTime,
			"AccountFacet: Too many deallocate in a short window"
		);
		
		// Check sufficient allocated balance using encrypted comparison
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[msg.sender].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtBool gtSufficientBalance = gtCurrentBalance.ge(gtAmount);
		require(MpcCore.decrypt(gtSufficientBalance), "AccountFacet: Insufficient allocated Balance");
		
		LibMuonAccount.verifyPartyAUpnl(upnlSig, msg.sender);
		gtInt256 gtAvailableBalance = LibAccount.partyAAvailableForQuote(upnlSig.upnl, msg.sender);
		gtBool gtAvailableBalanceNonNegative = LibAccount.isNonNegative(gtAvailableBalance);
		require(MpcCore.decrypt(gtAvailableBalanceNonNegative), "AccountFacet: Available balance is lower than zero");
		gtBool gtAvailableBalanceCoversAmount = LibAccount.isAtLeastAmount(gtAvailableBalance, gtAmount);
		require(MpcCore.decrypt(gtAvailableBalanceCoversAmount), "AccountFacet: partyA will be liquidatable");

		// Update encrypted balance
		gtUint256 gtNewBalance = gtCurrentBalance.checkedSub(gtAmount);
		_storePartyAAllocatedBalance(accountLayout, msg.sender, gtNewBalance);
		accountLayout.balances[msg.sender] += amount;
		accountLayout.withdrawCooldown[msg.sender] = block.timestamp;
	}

	function transferAllocation(uint256 amount, address origin, address recipient, SingleUpnlSig memory upnlSig) internal {
		MAStorage.Layout storage maLayout = MAStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(!maLayout.partyBLiquidationStatus[msg.sender][origin], "PartyBFacet: PartyB isn't solvent");
		require(!maLayout.partyBLiquidationStatus[msg.sender][recipient], "PartyBFacet: PartyB isn't solvent");
		require(!MAStorage.layout().liquidationStatus[origin], "PartyBFacet: Origin isn't solvent");
		require(!MAStorage.layout().liquidationStatus[recipient], "PartyBFacet: Recipient isn't solvent");
		
		// Initialize Party B encrypted values for both origin and recipient if uninitialized
		LibAccount.initializePartyB(msg.sender, origin);
		LibAccount.initializePartyB(msg.sender, recipient);
		
		LibMuonAccount.verifyPartyBUpnl(upnlSig, msg.sender, origin);
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableForQuote(upnlSig.upnl, msg.sender, origin);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtBool gtAvailableBalanceNonNegative = LibAccount.isNonNegative(gtAvailableBalance);
		require(MpcCore.decrypt(gtAvailableBalanceNonNegative), "PartyBFacet: Available balance is lower than zero");
		gtBool gtAvailableBalanceCoversAmount = LibAccount.isAtLeastAmount(gtAvailableBalance, gtAmount);
		require(MpcCore.decrypt(gtAvailableBalanceCoversAmount), "PartyBFacet: Will be liquidatable");

		// Check sufficient balance using encrypted comparison
		gtUint256 gtOriginBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[msg.sender][origin].ciphertext);
		gtBool gtSufficientBalance = gtOriginBalance.ge(gtAmount);
		require(MpcCore.decrypt(gtSufficientBalance), "PartyBFacet: Insufficient locked balance");

		// Self-transfers are a no-op. Preserve the original sequential semantics
		// instead of re-reading and overwriting the same encrypted balance slot.
		if (origin == recipient) {
			return;
		}

		// Update encrypted balances
		gtUint256 gtNewOriginBalance = gtOriginBalance.checkedSub(gtAmount);
		gtUint256 gtRecipientBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[msg.sender][recipient].ciphertext);
		gtUint256 gtNewRecipientBalance = gtRecipientBalance.checkedAdd(gtAmount);
		
		_storePartyBAllocatedBalance(accountLayout, msg.sender, origin, gtNewOriginBalance);
		_storePartyBAllocatedBalance(accountLayout, msg.sender, recipient, gtNewRecipientBalance);
	}

	function internalTransfer(address user, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		LibAccount.initializePartyA(user);

		// Check limit using encrypted comparison
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[user].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtUint256 gtLimit = MpcCore.setPublic256(GlobalAppStorage.layout().balanceLimitPerUser);
		
		gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtAmount);
		gtBool gtWithinLimit = gtNewBalance.le(gtLimit);
		require(MpcCore.decrypt(gtWithinLimit), "AccountFacet: Allocated balance limit reached");
		
		require(accountLayout.balances[msg.sender] >= amount, "AccountFacet: Insufficient balance");
		accountLayout.balances[msg.sender] -= amount;
		
		// Store encrypted new balance
		_storePartyAAllocatedBalance(accountLayout, user, gtNewBalance);
	}

	function allocateForPartyB(uint256 amount, address partyA) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// Initialize Party B encrypted values for this Party A if uninitialized
		LibAccount.initializePartyB(msg.sender, partyA);

		require(accountLayout.balances[msg.sender] >= amount, "AccountFacet: Insufficient balance");
		require(!MAStorage.layout().partyBLiquidationStatus[msg.sender][partyA], "AccountFacet: PartyB isn't solvent");
		accountLayout.balances[msg.sender] -= amount;
		
		// Update encrypted partyB allocated balance
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[msg.sender][partyA].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtAmount);
		_storePartyBAllocatedBalance(accountLayout, msg.sender, partyA, gtNewBalance);
	}

	function deallocateForPartyB(uint256 amount, address partyA, SingleUpnlSig memory upnlSig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		
		// Check sufficient allocated balance using encrypted comparison
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[msg.sender][partyA].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtBool gtSufficientBalance = gtCurrentBalance.ge(gtAmount);
		require(MpcCore.decrypt(gtSufficientBalance), "AccountFacet: Insufficient allocated balance");
		
		LibMuonAccount.verifyPartyBUpnl(upnlSig, msg.sender, partyA);
		gtInt256 gtAvailableBalance = LibAccount.partyBAvailableForQuote(upnlSig.upnl, msg.sender, partyA);
		gtBool gtAvailableBalanceNonNegative = LibAccount.isNonNegative(gtAvailableBalance);
		require(MpcCore.decrypt(gtAvailableBalanceNonNegative), "AccountFacet: Available balance is lower than zero");
		gtBool gtAvailableBalanceCoversAmount = LibAccount.isAtLeastAmount(gtAvailableBalance, gtAmount);
		require(MpcCore.decrypt(gtAvailableBalanceCoversAmount), "AccountFacet: Will be liquidatable");

		// Update encrypted balance
		gtUint256 gtNewBalance = gtCurrentBalance.checkedSub(gtAmount);
		_storePartyBAllocatedBalance(accountLayout, msg.sender, partyA, gtNewBalance);
		accountLayout.balances[msg.sender] += amount;
		accountLayout.withdrawCooldown[msg.sender] = block.timestamp;
	}

	function depositToReserveVault(uint256 amount, address partyB) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(amount <= accountLayout.balances[msg.sender], "AccountFacet: Insufficient balance");
		require(MAStorage.layout().partyBStatus[partyB], "AccountFacet: Should be partyB");
		accountLayout.balances[msg.sender] -= amount;
		gtUint256 gtCurrentReserveVault = LibAccount.initializeReserveVault(partyB);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtUint256 gtNewReserveVault = gtCurrentReserveVault.checkedAdd(gtAmount);
		_storeReserveVault(accountLayout, partyB, gtNewReserveVault);
	}

	function withdrawFromReserveVault(uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(amount > 0, "AccountFacet: Insufficient balance");
		gtUint256 gtCurrentReserveVault = LibAccount.initializeReserveVault(msg.sender);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		require(MpcCore.decrypt(gtCurrentReserveVault.ge(gtAmount)), "AccountFacet: Insufficient balance");
		gtUint256 gtNewReserveVault = gtCurrentReserveVault.checkedSub(gtAmount);
		_storeReserveVault(accountLayout, msg.sender, gtNewReserveVault);
		accountLayout.balances[msg.sender] += amount;
		accountLayout.withdrawCooldown[msg.sender] = block.timestamp;
	}

	function claimFeeCollectorBalance(uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(amount > 0, "AccountFacet: Insufficient balance");
		gtUint256 gtCurrentFeeBalance = LibAccount.initializeFeeCollectorBalance(msg.sender);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		require(MpcCore.decrypt(gtCurrentFeeBalance.ge(gtAmount)), "AccountFacet: Insufficient fee balance");
		gtUint256 gtNewFeeBalance = gtCurrentFeeBalance.checkedSub(gtAmount);
		_storeFeeCollectorBalance(accountLayout, msg.sender, gtNewFeeBalance);
		accountLayout.balances[msg.sender] += amount;
	}

	function setEncryptionAddress(address user, address newEncryptionAddress) internal {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        address currentMapped = accountLayout.userEncryptionAddress[user];
        address effectiveCurrent = currentMapped == address(0) ? user : currentMapped;
        require(newEncryptionAddress != address(0), "AccountFacet: zero encryption address");
        require(newEncryptionAddress != effectiveCurrent, "AccountFacet: encryption address unchanged");

        // Re-encrypt AccountStorage values owned by user
        accountLayout.allocatedBalances[user] = MpcCore.offBoardCombined(
            LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[user].ciphertext),
            newEncryptionAddress
        );
		accountLayout.observerAllocatedBalances[user] = LibEncryption.offBoardToObserver(
			LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[user].ciphertext)
		);

        GarbledLockedValues memory gtLocked = LockedValuesOps.onBoard(accountLayout.lockedBalances[user]);
        accountLayout.lockedBalances[user] = LockedValuesOps.offBoard(gtLocked, newEncryptionAddress);
        GarbledLockedValues memory gtPendingLocked = LockedValuesOps.onBoard(accountLayout.pendingLockedBalances[user]);
        accountLayout.pendingLockedBalances[user] = LockedValuesOps.offBoard(gtPendingLocked, newEncryptionAddress);
		gtUint256 gtReserveVault = LibAccount.initializeReserveVault(user);
		accountLayout.encryptedReserveVault[user] = MpcCore.offBoardCombined(gtReserveVault, newEncryptionAddress);
		accountLayout.observerEncryptedReserveVault[user] = LibEncryption.offBoardToObserver(gtReserveVault);
		gtUint256 gtFeeCollectorBalance = LibAccount.initializeFeeCollectorBalance(user);
		accountLayout.encryptedFeeCollectorBalances[user] = MpcCore.offBoardCombined(gtFeeCollectorBalance, newEncryptionAddress);
		accountLayout.observerEncryptedFeeCollectorBalances[user] = LibEncryption.offBoardToObserver(gtFeeCollectorBalance);
		gtUint256 gtPartyAReimbursement = LibAccount.initializePartyAReimbursement(user);
		accountLayout.encryptedPartyAReimbursement[user] = MpcCore.offBoardCombined(gtPartyAReimbursement, newEncryptionAddress);
		accountLayout.observerEncryptedPartyAReimbursement[user] = LibEncryption.offBoardToObserver(gtPartyAReimbursement);

        // Re-encrypt all quotes owned by user
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        uint256[] storage ids = quoteLayout.quoteIdsOf[user];
        for (uint256 i = 0; i < ids.length; i++) {
            Quote storage q = quoteLayout.quotes[ids[i]];
            if (q.partyA != user) continue;
			ObserverQuoteValues storage observerValues = quoteLayout.observerQuoteValues[ids[i]];

            q.openedPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.openedPrice.ciphertext), newEncryptionAddress);
            observerValues.openedPrice = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.openedPrice.ciphertext));
            q.initialOpenedPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.initialOpenedPrice.ciphertext), newEncryptionAddress);
            observerValues.initialOpenedPrice = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.initialOpenedPrice.ciphertext));
            q.requestedOpenPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.requestedOpenPrice.ciphertext), newEncryptionAddress);
            observerValues.requestedOpenPrice = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.requestedOpenPrice.ciphertext));
            q.marketPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.marketPrice.ciphertext), newEncryptionAddress);
            observerValues.marketPrice = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.marketPrice.ciphertext));
            q.quantity = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.quantity.ciphertext), newEncryptionAddress);
            observerValues.quantity = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.quantity.ciphertext));
            q.closedAmount = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.closedAmount.ciphertext), newEncryptionAddress);
            observerValues.closedAmount = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.closedAmount.ciphertext));
            q.avgClosedPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.avgClosedPrice.ciphertext), newEncryptionAddress);
            observerValues.avgClosedPrice = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.avgClosedPrice.ciphertext));
            q.requestedClosePrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.requestedClosePrice.ciphertext), newEncryptionAddress);
            observerValues.requestedClosePrice = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.requestedClosePrice.ciphertext));
            q.quantityToClose = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.quantityToClose.ciphertext), newEncryptionAddress);
            observerValues.quantityToClose = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.quantityToClose.ciphertext));
            q.tradingFee = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.tradingFee.ciphertext), newEncryptionAddress);
            observerValues.tradingFee = LibEncryption.offBoardToObserver(LockedValuesOps.safeOnboard(q.tradingFee.ciphertext));

            GarbledLockedValues memory gtInit = LockedValuesOps.onBoard(q.initialLockedValues);
            q.initialLockedValues = LockedValuesOps.offBoard(gtInit, newEncryptionAddress);
            observerValues.initialLockedValues = _offBoardLockedValuesToObserver(gtInit);
            GarbledLockedValues memory gtCurr = LockedValuesOps.onBoard(q.lockedValues);
            q.lockedValues = LockedValuesOps.offBoard(gtCurr, newEncryptionAddress);
            observerValues.lockedValues = _offBoardLockedValuesToObserver(gtCurr);
        }

		address[] storage partyAs = accountLayout.partyBConnectedPartyAs[user];
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			require(!MAStorage.layout().partyBLiquidationStatus[user][partyA], "Accessibility: PartyB isn't solvent");

			gtUint256 gtPartyBAllocatedBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[user][partyA].ciphertext);
			accountLayout.partyBAllocatedBalances[user][partyA] = MpcCore.offBoardCombined(gtPartyBAllocatedBalance, newEncryptionAddress);
			accountLayout.observerPartyBAllocatedBalances[user][partyA] = LibEncryption.offBoardToObserver(gtPartyBAllocatedBalance);

			GarbledLockedValues memory gtPartyBLocked = accountLayout.partyBLockedBalances[user][partyA].onBoard();
			accountLayout.partyBLockedBalances[user][partyA] = gtPartyBLocked.offBoard(newEncryptionAddress);
			accountLayout.observerPartyBLockedBalances[user][partyA] = LibEncryption.offBoardLockedToObserver(gtPartyBLocked);

			GarbledLockedValues memory gtPartyBPendingLocked = accountLayout.partyBPendingLockedBalances[user][partyA].onBoard();
			accountLayout.partyBPendingLockedBalances[user][partyA] = gtPartyBPendingLocked.offBoard(newEncryptionAddress);
			accountLayout.observerPartyBPendingLockedBalances[user][partyA] = LibEncryption.offBoardLockedToObserver(gtPartyBPendingLocked);
		}

		accountLayout.userEncryptionAddress[user] = newEncryptionAddress;
    }

	function _storePartyAAllocatedBalance(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) private {
		accountLayout.allocatedBalances[partyA] = LibEncryption.offBoardToUser(value, partyA);
		accountLayout.observerAllocatedBalances[partyA] = LibEncryption.offBoardToObserver(value);
	}

	function _storePartyBAllocatedBalance(AccountStorage.Layout storage accountLayout, address partyB, address partyA, gtUint256 value) private {
		accountLayout.partyBAllocatedBalances[partyB][partyA] = LibEncryption.offBoardToUser(value, partyB);
		accountLayout.observerPartyBAllocatedBalances[partyB][partyA] = LibEncryption.offBoardToObserver(value);
	}

	function _storeReserveVault(AccountStorage.Layout storage accountLayout, address partyB, gtUint256 value) private {
		accountLayout.encryptedReserveVault[partyB] = LibEncryption.offBoardToUser(value, partyB);
		accountLayout.observerEncryptedReserveVault[partyB] = LibEncryption.offBoardToObserver(value);
	}

	function _storeFeeCollectorBalance(AccountStorage.Layout storage accountLayout, address feeCollector, gtUint256 value) private {
		accountLayout.encryptedFeeCollectorBalances[feeCollector] = LibEncryption.offBoardToUser(value, feeCollector);
		accountLayout.observerEncryptedFeeCollectorBalances[feeCollector] = LibEncryption.offBoardToObserver(value);
	}

	function _offBoardLockedValuesToObserver(GarbledLockedValues memory values) private returns (UserLockedValues memory) {
		address observer = LibEncryption.getObserverEncryptionAddress();
		if (observer == address(0)) {
			return UserLockedValues({
				cva: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) }),
				lf: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) }),
				partyAmm: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) }),
				partyBmm: ctUint256({ ciphertextHigh: ctUint128.wrap(0), ciphertextLow: ctUint128.wrap(0) })
			});
		}
		return LockedValuesOps.offBoardToUser(values, observer);
	}
}
