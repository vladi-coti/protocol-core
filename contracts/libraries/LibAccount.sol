// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./LibLockedValues.sol";
import "../storages/AccountStorage.sol";

library LibAccount {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	/**
	 * @notice Returns the encryption address for a user.
	 * @param user The address of the user.
	 * @return The encryption address for the user.
	 */
	function getUserEncryptionAddress(address user) internal view returns (address) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		return accountLayout.userEncryptionAddress[user];
	}

	/**
	 * @notice Calculates the total locked balances of Party A.
	 * @param partyA The address of Party A.
	 * @return The total locked balances of Party A (encrypted).
	 */
	function partyATotalLockedBalances(address partyA) internal returns (gtUint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.pendingLockedBalances[partyA].onBoard();
		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();

		return garbledPendingLockedBalances.totalForPartyA().add(garbledLockedBalances.totalForPartyA());
	}

	/**
	 * @notice Calculates the total locked balances of Party B for a specific Party A.
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The total locked balances of Party B for the specified Party A (encrypted).
	 */
	function partyBTotalLockedBalances(address partyB, address partyA) internal returns (gtUint256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.partyBPendingLockedBalances[partyB][partyA].onBoard();
		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		return garbledPendingLockedBalances.totalForPartyB().add(garbledLockedBalances.totalForPartyB());
	}

	/**
	 * @notice Calculates the available balance for a quote for Party A.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyA The address of Party A.
	 * @return The available balance for a quote for Party A (encrypted).
	 */
	function partyAAvailableForQuote(int256 upnl, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = MpcCore.toSigned(MpcCore.setPublic256(accountLayout.allocatedBalances[partyA]));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);
		
		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();
		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.pendingLockedBalances[partyA].onBoard();
		
		gtInt256 totalLocked = MpcCore.toSigned(garbledLockedBalances.totalForPartyA().add(garbledPendingLockedBalances.totalForPartyA()));
		
		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.add(gtUpnl).sub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyAmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = MpcCore.toSigned(garbledLockedBalances.partyAmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, negUpnl, mm);
			
			gtInt256 cvaLfPendingTotal = MpcCore.toSigned(garbledLockedBalances.cva.add(garbledLockedBalances.lf).add(garbledPendingLockedBalances.totalForPartyA()));
			return allocatedBalance.sub(cvaLfPendingTotal).sub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for Party A.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyA The address of Party A.
	 * @return The available balance for Party A (encrypted).
	 */
	function partyAAvailableBalance(int256 upnl, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = MpcCore.toSigned(MpcCore.setPublic256(accountLayout.allocatedBalances[partyA]));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);
		
		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();
		gtInt256 totalLocked = MpcCore.toSigned(garbledLockedBalances.totalForPartyA());
		
		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.add(gtUpnl).sub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyAmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = MpcCore.toSigned(garbledLockedBalances.partyAmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, negUpnl, mm);
			
			gtInt256 cvaLf = MpcCore.toSigned(garbledLockedBalances.cva.add(garbledLockedBalances.lf));
			return allocatedBalance.sub(cvaLf).sub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party A.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param allocatedBalance The allocatedBalance of Party A.
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party A (encrypted).
	 */
	function partyAAvailableBalanceForLiquidation(int256 upnl, uint256 allocatedBalance, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalanceEncrypted = MpcCore.toSigned(MpcCore.setPublic256(allocatedBalance));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);
		
		GarbledLockedValues memory garbledLockedBalances = accountLayout.lockedBalances[partyA].onBoard();
		gtInt256 cvaLf = MpcCore.toSigned(garbledLockedBalances.cva.add(garbledLockedBalances.lf));
		
		gtInt256 freeBalance = allocatedBalanceEncrypted.sub(cvaLf);
		return freeBalance.add(gtUpnl);
	}

	/**
	 * @notice Calculates the available balance for a quote for Party B.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for a quote for Party B (encrypted).
	 */
	function partyBAvailableForQuote(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = MpcCore.toSigned(MpcCore.setPublic256(accountLayout.partyBAllocatedBalances[partyB][partyA]));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);
		
		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		GarbledLockedValues memory garbledPendingLockedBalances = accountLayout.partyBPendingLockedBalances[partyB][partyA].onBoard();
		
		gtInt256 totalLocked = MpcCore.toSigned(garbledLockedBalances.totalForPartyB().add(garbledPendingLockedBalances.totalForPartyB()));
		
		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.add(gtUpnl).sub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyBmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = MpcCore.toSigned(garbledLockedBalances.partyBmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, negUpnl, mm);
			
			gtInt256 cvaLfPendingTotal = MpcCore.toSigned(garbledLockedBalances.cva.add(garbledLockedBalances.lf).add(garbledPendingLockedBalances.totalForPartyB()));
			return allocatedBalance.sub(cvaLfPendingTotal).sub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for Party B.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for Party B (encrypted).
	 */
	function partyBAvailableBalance(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalance = MpcCore.toSigned(MpcCore.setPublic256(accountLayout.partyBAllocatedBalances[partyB][partyA]));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);
		
		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		gtInt256 totalLocked = MpcCore.toSigned(garbledLockedBalances.totalForPartyB());
		
		if (upnl >= 0) {
			// If upnl >= 0: available = allocatedBalance + upnl - totalLocked
			return allocatedBalance.add(gtUpnl).sub(totalLocked);
		} else {
			// If upnl < 0: considering_mm = max(-upnl, partyBmm)
			gtInt256 negUpnl = MpcCore.setPublic256(-upnl);
			gtInt256 mm = MpcCore.toSigned(garbledLockedBalances.partyBmm);
			gtBool negUpnlGreaterThanMm = negUpnl.gt(mm);
			gtInt256 considering_mm = MpcCore.mux(negUpnlGreaterThanMm, negUpnl, mm);
			
			gtInt256 cvaLf = MpcCore.toSigned(garbledLockedBalances.cva.add(garbledLockedBalances.lf));
			return allocatedBalance.sub(cvaLf).sub(considering_mm);
		}
	}

	/**
	 * @notice Calculates the available balance for liquidation for Party B.
	 * @param upnl The unrealized profit and loss (unencrypted).
	 * @param partyB The address of Party B.
	 * @param partyA The address of Party A.
	 * @return The available balance for liquidation for Party B (encrypted).
	 */
	function partyBAvailableBalanceForLiquidation(int256 upnl, address partyB, address partyA) internal returns (gtInt256) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		gtInt256 allocatedBalanceEncrypted = MpcCore.toSigned(MpcCore.setPublic256(accountLayout.partyBAllocatedBalances[partyB][partyA]));
		gtInt256 gtUpnl = MpcCore.setPublic256(upnl);
		
		GarbledLockedValues memory garbledLockedBalances = accountLayout.partyBLockedBalances[partyB][partyA].onBoard();
		gtInt256 cvaLf = MpcCore.toSigned(garbledLockedBalances.cva.add(garbledLockedBalances.lf));
		
		gtInt256 freeBalance = allocatedBalanceEncrypted.sub(cvaLf);
		return freeBalance.add(gtUpnl);
	}
}
