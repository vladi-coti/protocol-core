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

library AccountFacetImpl {
	using SafeERC20 for IERC20;
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;

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
		gtUint256 gtNewBalance = gtCurrentBalance.add(gtAmount);
		gtBool gtWithinLimit = gtNewBalance.le(gtLimit);
		require(MpcCore.decrypt(gtWithinLimit), "AccountFacet: Allocated balance limit reached");
		
		require(accountLayout.balances[msg.sender] >= amount, "AccountFacet: Insufficient balance");
		accountLayout.balances[msg.sender] -= amount;
		
		// Store encrypted new balance
		accountLayout.allocatedBalances[msg.sender] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(msg.sender));
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
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
		require(availableBalance >= 0, "AccountFacet: Available balance is lower than zero");
		require(uint256(availableBalance) >= amount, "AccountFacet: partyA will be liquidatable");

		// Update encrypted balance
		gtUint256 gtNewBalance = gtCurrentBalance.sub(gtAmount);
		accountLayout.allocatedBalances[msg.sender] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(msg.sender));
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
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
		require(availableBalance >= 0, "PartyBFacet: Available balance is lower than zero");
		require(uint256(availableBalance) >= amount, "PartyBFacet: Will be liquidatable");

		// Check sufficient balance using encrypted comparison
		gtUint256 gtOriginBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[msg.sender][origin].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtBool gtSufficientBalance = gtOriginBalance.ge(gtAmount);
		require(MpcCore.decrypt(gtSufficientBalance), "PartyBFacet: Insufficient locked balance");

		// Update encrypted balances
		gtUint256 gtNewOriginBalance = gtOriginBalance.sub(gtAmount);
		gtUint256 gtRecipientBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[msg.sender][recipient].ciphertext);
		gtUint256 gtNewRecipientBalance = gtRecipientBalance.add(gtAmount);
		
		accountLayout.partyBAllocatedBalances[msg.sender][origin] = MpcCore.offBoardCombined(gtNewOriginBalance, LibAccount.getUserEncryptionAddress(msg.sender));
		accountLayout.partyBAllocatedBalances[msg.sender][recipient] = MpcCore.offBoardCombined(gtNewRecipientBalance, LibAccount.getUserEncryptionAddress(msg.sender));
	}

	function internalTransfer(address user, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// Check limit using encrypted comparison
		gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[user].ciphertext);
		gtUint256 gtAmount = MpcCore.setPublic256(amount);
		gtUint256 gtLimit = MpcCore.setPublic256(GlobalAppStorage.layout().balanceLimitPerUser);
		
		gtUint256 gtNewBalance = gtCurrentBalance.add(gtAmount);
		gtBool gtWithinLimit = gtNewBalance.le(gtLimit);
		require(MpcCore.decrypt(gtWithinLimit), "AccountFacet: Allocated balance limit reached");
		
		require(accountLayout.balances[msg.sender] >= amount, "AccountFacet: Insufficient balance");
		accountLayout.balances[msg.sender] -= amount;
		
		// Store encrypted new balance
		accountLayout.allocatedBalances[user] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(user));
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
		gtUint256 gtNewBalance = gtCurrentBalance.add(gtAmount);
		accountLayout.partyBAllocatedBalances[msg.sender][partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(msg.sender));
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
		int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
		require(availableBalance >= 0, "AccountFacet: Available balance is lower than zero");
		require(uint256(availableBalance) >= amount, "AccountFacet: Will be liquidatable");

		// Update encrypted balance
		gtUint256 gtNewBalance = gtCurrentBalance.sub(gtAmount);
		accountLayout.partyBAllocatedBalances[msg.sender][partyA] = MpcCore.offBoardCombined(gtNewBalance, LibAccount.getUserEncryptionAddress(msg.sender));
		accountLayout.balances[msg.sender] += amount;
		accountLayout.withdrawCooldown[msg.sender] = block.timestamp;
	}

	function depositToReserveVault(uint256 amount, address partyB) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(amount <= accountLayout.balances[msg.sender], "AccountFacet: Insufficient balance");
		require(MAStorage.layout().partyBStatus[partyB], "AccountFacet: Should be partyB");
		accountLayout.balances[msg.sender] -= amount;
		accountLayout.reserveVault[partyB] += amount;
	}

	function withdrawFromReserveVault(uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(amount > 0 && amount <= accountLayout.reserveVault[msg.sender], "AccountFacet: Insufficient balance");
		accountLayout.reserveVault[msg.sender] -= amount;
		accountLayout.balances[msg.sender] += amount;
		accountLayout.withdrawCooldown[msg.sender] = block.timestamp;
	}

	function setEncryptionAddress(address user, address newEncryptionAddress) internal {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        address currentMapped = accountLayout.userEncryptionAddress[user];
        address effectiveCurrent = currentMapped == address(0) ? user : currentMapped;
        require(newEncryptionAddress != address(0), "AccountFacet: zero encryption address");
        require(newEncryptionAddress != effectiveCurrent, "AccountFacet: encryption address unchanged");

        accountLayout.userEncryptionAddress[user] = newEncryptionAddress;

		if(accountLayout.trustedEncryptionAddress != address(0)) {
			return;
		}

        // Re-encrypt AccountStorage values owned by user
        accountLayout.allocatedBalances[user] = MpcCore.offBoardCombined(
            LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[user].ciphertext),
            newEncryptionAddress
        );

        GarbledLockedValues memory gtLocked = LockedValuesOps.onBoard(accountLayout.lockedBalances[user]);
        accountLayout.lockedBalances[user] = LockedValuesOps.offBoard(gtLocked, newEncryptionAddress);
        GarbledLockedValues memory gtPendingLocked = LockedValuesOps.onBoard(accountLayout.pendingLockedBalances[user]);
        accountLayout.pendingLockedBalances[user] = LockedValuesOps.offBoard(gtPendingLocked, newEncryptionAddress);

        // Re-encrypt all quotes owned by user
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        uint256[] storage ids = quoteLayout.quoteIdsOf[user];
        for (uint256 i = 0; i < ids.length; i++) {
            Quote storage q = quoteLayout.quotes[ids[i]];
            if (q.partyA != user) continue;

            q.openedPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.openedPrice.ciphertext), newEncryptionAddress);
            q.initialOpenedPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.initialOpenedPrice.ciphertext), newEncryptionAddress);
            q.requestedOpenPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.requestedOpenPrice.ciphertext), newEncryptionAddress);
            q.marketPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.marketPrice.ciphertext), newEncryptionAddress);
            q.quantity = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.quantity.ciphertext), newEncryptionAddress);
            q.closedAmount = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.closedAmount.ciphertext), newEncryptionAddress);
            q.avgClosedPrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.avgClosedPrice.ciphertext), newEncryptionAddress);
            q.requestedClosePrice = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.requestedClosePrice.ciphertext), newEncryptionAddress);
            q.quantityToClose = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.quantityToClose.ciphertext), newEncryptionAddress);
            q.tradingFee = MpcCore.offBoardCombined(LockedValuesOps.safeOnboard(q.tradingFee.ciphertext), newEncryptionAddress);

            GarbledLockedValues memory gtInit = LockedValuesOps.onBoard(q.initialLockedValues);
            q.initialLockedValues = LockedValuesOps.offBoard(gtInit, newEncryptionAddress);
            GarbledLockedValues memory gtCurr = LockedValuesOps.onBoard(q.lockedValues);
            q.lockedValues = LockedValuesOps.offBoard(gtCurr, newEncryptionAddress);
        }
    }
}
