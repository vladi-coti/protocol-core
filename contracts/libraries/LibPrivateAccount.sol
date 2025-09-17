// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./LibLockedPrivateValues.sol";
import "../storages/PrivateAccountStorage.sol";

library LibPrivateAccount {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedPrivateValuesOps for PrivateLockedValues;
	using LockedPrivateValuesOps for GarbledPrivateLockedValues;

	/**
	 * @notice Gets the user encryption address.
	 * @param user The address of the user.
	 * @return The user encryption address.
	 */
	function getUserEncryptionAddress(address user) internal returns (address) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		address encryptionAddress = privateAccountLayout.userEncryptionAddress[user];
		if (encryptionAddress == address(0)) {
			encryptionAddress = user;
		}
		return encryptionAddress;
	}

	/**
	 * @notice Calculates the total locked balances of Party A.
	 * @param partyA The address of Party A.
	 * @return The total locked balances of Party A.
	 */
	function partyATotalLockedBalances(address partyA) internal returns (gtUint256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		// Add encrypted pending and locked balances for Party A
		PrivateLockedValues memory totalPending = privateAccountLayout.encryptedPendingLockedBalances[partyA];
		PrivateLockedValues memory totalLocked = privateAccountLayout.encryptedLockedBalances[partyA];
		gtUint256 pendingTotal = totalPending.onBoard().totalForPartyA();
		gtUint256 lockedTotal = totalLocked.onBoard().totalForPartyA();
		gtUint256 grandTotal = pendingTotal.add(lockedTotal);
		return grandTotal;
	}

	/**
	 * @notice Calculates the total locked balances of Party B for a specific Party A.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The total locked balances of Party B for the specified Party A.
	 */
	function partyBTotalLockedBalances(address partyB, address partyA) internal returns (gtUint256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		// Add encrypted pending and locked balances for Party B
		PrivateLockedValues memory totalPending = privateAccountLayout.partyBEncryptedPendingLockedBalances[partyB][partyA];
		PrivateLockedValues memory totalLocked = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA];
		gtUint256 pendingTotal = totalPending.onBoard().totalForPartyB();
		gtUint256 lockedTotal = totalLocked.onBoard().totalForPartyB();
		gtUint256 grandTotal = pendingTotal.add(lockedTotal);
		return grandTotal;
	}

	/**
	 * @notice Calculates the available balance for a quote for Party A.
	 * @param upnl The unrealized profit and loss.
	 * @param partyA The address of Party A.
	 * @return The available balance for a quote for Party A.
	 */
	function partyAAvailableForQuote(int256 upnl, address partyA) internal returns (gtInt256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		gtUint256 allocatedBalance = MpcCore.setPublic256(privateAccountLayout.allocatedBalances[partyA]);
		gtInt256 gtUpnl = MpcCore.setPublic256(int256(upnl));

		if (upnl >= 0) {
			// Calculate total locked amounts using encrypted operations
			PrivateLockedValues memory pending = privateAccountLayout.encryptedPendingLockedBalances[partyA];
			PrivateLockedValues memory locked = privateAccountLayout.encryptedLockedBalances[partyA];
			gtUint256 totalLockedAmount = locked.onBoard().totalForPartyA().add(pending.onBoard().totalForPartyA());

			gtInt256 available = allocatedBalance.toSigned().add(gtUpnl).sub(totalLockedAmount.toSigned());
			return available;
		} else {
			// Get gt partyAmm for comparison
			gtUint256 gtMm = privateAccountLayout.encryptedLockedBalances[partyA].onBoard().partyAmm;
			gtInt256 negUpnl = gtUpnl.negate();
			gtInt256 mm = gtMm.toSigned();
			gtBool condition = negUpnl.gt(mm);
			gtInt256 considering_mm = condition.mux(negUpnl, mm);

			// Calculate CVA + LF + pending total using gt operations
			PrivateLockedValues memory locked = privateAccountLayout.encryptedLockedBalances[partyA];
			PrivateLockedValues memory pending = privateAccountLayout.encryptedPendingLockedBalances[partyA];
			gtUint256 cvaLfAmount = locked.onBoard().cva.add(locked.onBoard().lf);
			gtUint256 pendingTotal = pending.onBoard().totalForPartyA();
			gtUint256 totalAmount = cvaLfAmount.add(pendingTotal);

			gtInt256 available = allocatedBalance.toSigned().sub(totalAmount.toSigned()).sub(considering_mm);
			return available;
		}
	}

	/**
	 * @notice Calculates the available balance for Party A.
	 * @param upnl The unrealized profit and loss.
	 * @param partyA The address of Party A.
	 * @return The available balance for Party A.
	 */
	function partyAAvailableBalance(int256 upnl, address partyA) internal returns (gtInt256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		gtUint256 allocatedBalance = MpcCore.setPublic256(privateAccountLayout.allocatedBalances[partyA]);
		gtInt256 gtUpnl = MpcCore.setPublic256(int256(upnl));

		if (upnl >= 0) {
			gtUint256 totalLocked = privateAccountLayout.encryptedLockedBalances[partyA].onBoard().totalForPartyA();
			gtInt256 available = allocatedBalance.toSigned().add(gtUpnl).sub(totalLocked.toSigned());
			return available;
		} else {
			gtUint256 gtMm = privateAccountLayout.encryptedLockedBalances[partyA].onBoard().partyAmm;
			gtInt256 negUpnl = gtUpnl.negate();
			gtInt256 mm = gtMm.toSigned();
			gtBool condition = negUpnl.gt(mm);
			gtInt256 considering_mm = condition.mux(negUpnl, mm);

			PrivateLockedValues memory locked = privateAccountLayout.encryptedLockedBalances[partyA];
			gtUint256 cvaLfAmount = locked.onBoard().cva.add(locked.onBoard().lf);

			gtInt256 available = allocatedBalance.toSigned().sub(cvaLfAmount.toSigned()).sub(considering_mm);
			return available;
		}
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party A.
	 * @param upnl The unrealized profit and loss.
	 * @param allocatedBalance The allocatedBalance of Party A.
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party A.
	 */
	function partyAAvailableBalanceForLiquidation(int256 upnl, uint256 allocatedBalance, address partyA) internal returns (gtInt256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		PrivateLockedValues memory locked = privateAccountLayout.encryptedLockedBalances[partyA];
		gtUint256 cvaLfAmount = locked.onBoard().cva.add(locked.onBoard().lf);
		gtInt256 gtAllocated = MpcCore.setPublic256(int256(allocatedBalance));
		gtInt256 gtUpnl = MpcCore.setPublic256(int256(upnl));
		gtInt256 freeBalance = gtAllocated.sub(cvaLfAmount.toSigned());
		return freeBalance.add(gtUpnl);
	}

	/**
	 * @notice Calculates the available balance for a quote for Party B.
	 * @param upnl The unrealized profit and loss.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for a quote for Party B.
	 */
	function partyBAvailableForQuote(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		gtUint256 allocatedBalance = MpcCore.setPublic256(privateAccountLayout.partyBAllocatedBalances[partyB][partyA]);
		gtInt256 gtUpnl = MpcCore.setPublic256(int256(upnl));

		if (upnl >= 0) {
			PrivateLockedValues memory pending = privateAccountLayout.partyBEncryptedPendingLockedBalances[partyB][partyA];
			PrivateLockedValues memory locked = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA];
			gtUint256 totalLockedAmount = locked.onBoard().totalForPartyB().add(pending.onBoard().totalForPartyB());

			gtInt256 available = allocatedBalance.toSigned().add(gtUpnl).sub(totalLockedAmount.toSigned());
			return available;
		} else {
			gtUint256 gtMm = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA].onBoard().partyBmm;
			gtInt256 negUpnl = gtUpnl.negate();
			gtInt256 mm = gtMm.toSigned();
			gtBool condition = negUpnl.gt(mm);
			gtInt256 considering_mm = condition.mux(negUpnl, mm);

			PrivateLockedValues memory locked = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA];
			PrivateLockedValues memory pending = privateAccountLayout.partyBEncryptedPendingLockedBalances[partyB][partyA];
			gtUint256 cvaLfAmount = locked.onBoard().cva.add(locked.onBoard().lf);
			gtUint256 pendingTotal = pending.onBoard().totalForPartyB();
			gtUint256 totalAmount = cvaLfAmount.add(pendingTotal);

			gtInt256 available = allocatedBalance.toSigned().sub(totalAmount.toSigned()).sub(considering_mm);
			return available;
		}
	}

	/**
	 * @notice Calculates the available balance for Party B.
	 * @param upnl The unrealized profit and loss.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for Party B.
	 */
	function partyBAvailableBalance(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		gtUint256 allocatedBalance = MpcCore.setPublic256(privateAccountLayout.partyBAllocatedBalances[partyB][partyA]);
		gtInt256 gtUpnl = MpcCore.setPublic256(int256(upnl));

		if (upnl >= 0) {
			gtUint256 totalLocked = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA].onBoard().totalForPartyB();
			gtInt256 available = allocatedBalance.toSigned().add(gtUpnl).sub(totalLocked.toSigned());
			return available;
		} else {
			gtUint256 gtMm = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA].onBoard().partyBmm;
			gtInt256 negUpnl = gtUpnl.negate();
			gtInt256 mm = gtMm.toSigned();
			gtBool condition = negUpnl.gt(mm);
			gtInt256 considering_mm = condition.mux(negUpnl, mm);

			PrivateLockedValues memory locked = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA];
			gtUint256 cvaLfAmount = locked.onBoard().cva.add(locked.onBoard().lf);

			gtInt256 available = allocatedBalance.toSigned().sub(cvaLfAmount.toSigned()).sub(considering_mm);
			return available;
		}
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party B.
	 * @param upnl The unrealized profit and loss.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party B.
	 */
	function partyBAvailableBalanceForLiquidation(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		PrivateLockedValues memory locked = privateAccountLayout.partyBEncryptedLockedBalances[partyB][partyA];
		gtUint256 cvaLfAmount = locked.onBoard().cva.add(locked.onBoard().lf);
		gtInt256 gtAllocated = MpcCore.setPublic256(int256(privateAccountLayout.partyBAllocatedBalances[partyB][partyA]));
		gtInt256 gtUpnl = MpcCore.setPublic256(int256(upnl));
		gtInt256 a = gtAllocated.sub(cvaLfAmount.toSigned());
		return a.add(gtUpnl);
	}
}
