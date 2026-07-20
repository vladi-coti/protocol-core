// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/MAStorage.sol";
import "../storages/MuonStorage.sol";
import "../storages/AccountStorage.sol";
import "./LibQuote.sol";
import "./LibAccount.sol";
import "./LibEncryption.sol";
import "./LibOnChainUpnl.sol";

library LibSettlement {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function settleUpnl(
		SettlementSig memory settleSig,
		uint256[] memory updatedPrices,
		address partyA,
		bool isForceClose
	) internal returns (utUint256[] memory newPartyBsAllocatedBalances) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(settleSig.quotesSettlementsData.length > 0 && settleSig.quotesSettlementsData.length == updatedPrices.length, "LibSettlement: Invalid length");
		
		// Check PartyA solvency using encrypted balance calculation
		gtInt256 gtPartyAUpnl = LibOnChainUpnl.partyAUpnlFromQuotePrices(partyA, settleSig.partyAPriceSig);
		gtInt256 gtPartyAAvailable = LibAccount.partyAAvailableBalanceForLiquidation(gtPartyAUpnl, partyA);
		gtInt256 gtZeroInt = MpcCore.setPublic256(int256(0));
		require(MpcCore.decrypt(gtPartyAAvailable.ge(gtZeroInt)), "LibSettlement: PartyA is insolvent");

		require(
			isForceClose || quoteLayout.partyBOpenPositions[msg.sender][partyA].length > 0,
			"LibSettlement: Sender should have a position with partyA"
		);
		accountLayout.partyANonces[partyA] += 1;

		gtInt256[] memory gtSettleAmounts = new gtInt256[](settleSig.partyBPriceSigs.length);
		address[] memory partyBs = new address[](settleSig.partyBPriceSigs.length);
		newPartyBsAllocatedBalances = new utUint256[](settleSig.partyBPriceSigs.length);
		for (uint256 i = 0; i < gtSettleAmounts.length; i++) {
			gtSettleAmounts[i] = gtZeroInt;
			require(settleSig.partyBPriceSigs[i].quoteIds.length > 0, "LibSettlement: Empty partyB prices");
			partyBs[i] = quoteLayout.quotes[settleSig.partyBPriceSigs[i].quoteIds[0]].partyB;
		}

		for (uint256 i = 0; i < settleSig.quotesSettlementsData.length; i++) {
			QuoteSettlementData memory data = settleSig.quotesSettlementsData[i];
			Quote storage quote = quoteLayout.quotes[data.quoteId];
			require(quote.partyA == partyA, "LibSettlement: PartyA is invalid");
			require(
				quote.quoteStatus == QuoteStatus.OPENED ||
					quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
					quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
				"LibSettlement: Invalid state"
			);
			uint256 partyBIndex = _partyBIndex(partyBs, quote.partyB);

			gtUint256 gtOpenedPrice = LockedValuesOps.safeOnboard(quote.openedPrice.ciphertext);
			gtUint256 gtCurrentPrice = MpcCore.setPublic256(data.currentPrice);
			gtUint256 gtUpdatedPrice = MpcCore.setPublic256(updatedPrices[i]);
			gtBool gtOpenedGtCurrent = gtOpenedPrice.gt(gtCurrentPrice);
			gtBool gtUpdatedLtOpened = gtUpdatedPrice.lt(gtOpenedPrice);
			gtBool gtUpdatedGtOpened = gtUpdatedPrice.gt(gtOpenedPrice);

			gtBool gtValidDownMove = gtUpdatedLtOpened.and(gtUpdatedPrice.ge(gtCurrentPrice));
			gtBool gtValidUpMove = gtUpdatedGtOpened.and(gtUpdatedPrice.le(gtCurrentPrice));
			gtBool gtValidUpdatedPrice = MpcCore.mux(gtOpenedGtCurrent, gtValidUpMove, gtValidDownMove);
			require(MpcCore.decrypt(gtValidUpdatedPrice), "LibSettlement: Updated price is out of range");

			gtUint256 gtQuoteOpenAmount = LibQuote.quoteOpenAmount(quote);
			gtUint256 gtPriceDiff = MpcCore.max(gtUpdatedPrice, gtOpenedPrice).checkedSub(MpcCore.min(gtUpdatedPrice, gtOpenedPrice));
			gtInt256 gtImpact = LibEncryption.toNonNegativeSigned(
				gtQuoteOpenAmount.checkedMul(gtPriceDiff).div(MpcCore.setPublic256(uint256(1e18)))
			);
			gtInt256 gtSignedImpact;

			if (quote.positionType == PositionType.LONG) {
				gtSignedImpact = MpcCore.mux(gtUpdatedGtOpened, gtZeroInt.checkedSub(gtImpact), gtImpact);
			} else {
				gtSignedImpact = MpcCore.mux(gtUpdatedGtOpened, gtImpact, gtZeroInt.checkedSub(gtImpact));
			}
			gtSettleAmounts[partyBIndex] = gtSettleAmounts[partyBIndex].checkedAdd(gtSignedImpact);

			LibEncryption.storeQuoteOpenedPrice(quoteLayout, quote, gtUpdatedPrice);
		}

		gtInt256 gtTotalSettlementAmount = gtZeroInt;
		for (uint256 i = 0; i < partyBs.length; i++) {
			address partyB = partyBs[i];
			
			// Check PartyB solvency using encrypted balance calculation
			gtInt256 gtPartyBUpnl = LibOnChainUpnl.partyBUpnlFromQuotePrices(partyB, partyA, settleSig.partyBPriceSigs[i]);
			gtInt256 gtPartyBAvailable = LibAccount.partyBAvailableBalanceForLiquidation(gtPartyBUpnl, partyB, partyA);
			require(MpcCore.decrypt(gtPartyBAvailable.ge(gtZeroInt)), "LibSettlement: PartyB should be solvent");
			
			require(!MAStorage.layout().partyBLiquidationStatus[partyB][partyA], "LibSettlement: PartyB is in liquidation process");

			if (!isForceClose && msg.sender != partyB) {
				require(
					block.timestamp >=
						MAStorage.layout().lastUpnlSettlementTimestamp[msg.sender][partyB][partyA] + MAStorage.layout().settlementCooldown,
					"LibSettlement: Cooldown should be passed"
				);
				MAStorage.layout().lastUpnlSettlementTimestamp[msg.sender][partyB][partyA] = block.timestamp;
			}
			accountLayout.partyBNonces[partyB][partyA] += 1;

			gtInt256 gtSettlementAmount = gtSettleAmounts[i];
			gtTotalSettlementAmount = gtTotalSettlementAmount.checkedAdd(gtSettlementAmount);

			// M-34: keep constant IN+OUT event shape (one encrypted zero), matching LibQuote close.
			gtBool gtPartyBPays = gtSettlementAmount.ge(gtZeroInt);
			gtUint256 gtZeroU = MpcCore.setPublic256(uint256(0));
			gtUint256 gtAmount = MpcCore.mux(
				gtPartyBPays,
				gtZeroInt.checkedSub(gtSettlementAmount).fromSigned(),
				gtSettlementAmount.fromSigned()
			);
			gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
			if (MpcCore.decrypt(gtPartyBPays)) {
				LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtPartyBBalance.checkedSub(gtAmount));
			} else {
				LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtPartyBBalance.checkedAdd(gtAmount));
			}
			address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
			gtUint256 gtPartyBPnlIn = MpcCore.mux(gtPartyBPays, gtAmount, gtZeroU);
			gtUint256 gtPartyBPnlOut = MpcCore.mux(gtPartyBPays, gtZeroU, gtAmount);
			emit SharedEvents.BalanceChangePartyB(
				partyB,
				partyA,
				MpcCore.offBoardToUser(gtPartyBPnlIn, partyBEncryptionAddress),
				SharedEvents.BalanceChangeType.REALIZED_PNL_IN
			);
			emit SharedEvents.BalanceChangePartyB(
				partyB,
				partyA,
				MpcCore.offBoardToUser(gtPartyBPnlOut, partyBEncryptionAddress),
				SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
			);
			// Store the new encrypted balance for return
			newPartyBsAllocatedBalances[i] = accountLayout.partyBAllocatedBalances[partyB][partyA];
		}

		gtBool gtPartyAGains = gtTotalSettlementAmount.ge(gtZeroInt);
		gtUint256 gtZeroU = MpcCore.setPublic256(uint256(0));
		gtUint256 gtAmount = MpcCore.mux(
			gtPartyAGains,
			gtZeroInt.checkedSub(gtTotalSettlementAmount).fromSigned(),
			gtTotalSettlementAmount.fromSigned()
		);
		gtUint256 gtPartyABalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
		if (MpcCore.decrypt(gtPartyAGains)) {
			LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtPartyABalance.checkedAdd(gtAmount));
		} else {
			LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtPartyABalance.checkedSub(gtAmount));
		}
		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
		gtUint256 gtPartyAPnlIn = MpcCore.mux(gtPartyAGains, gtZeroU, gtAmount);
		gtUint256 gtPartyAPnlOut = MpcCore.mux(gtPartyAGains, gtAmount, gtZeroU);
		emit SharedEvents.BalanceChangePartyA(
			partyA,
			MpcCore.offBoardToUser(gtPartyAPnlIn, partyAEncryptionAddress),
			SharedEvents.BalanceChangeType.REALIZED_PNL_IN
		);
		emit SharedEvents.BalanceChangePartyA(
			partyA,
			MpcCore.offBoardToUser(gtPartyAPnlOut, partyAEncryptionAddress),
			SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
		);
	}

	function _partyBIndex(address[] memory partyBs, address partyB) private pure returns (uint256) {
		for (uint256 i = 0; i < partyBs.length; i++) {
			if (partyBs[i] == partyB) {
				return i;
			}
		}
		revert("LibSettlement: Missing partyB price sig");
	}
}
