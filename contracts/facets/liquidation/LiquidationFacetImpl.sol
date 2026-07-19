// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibLockedValues.sol";
import "../../libraries/muon/LibMuonLiquidation.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibLiquidation.sol";
import "../../libraries/SharedEvents.sol";
import "../../libraries/LibEncryption.sol";
import "../../libraries/LibOnChainUpnl.sol";
import "../../storages/MAStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library LiquidationFacetImpl {
    using MpcCore for gtUint256;
    using MpcCore for gtInt256;
    using MpcCore for gtBool;
    using LockedValuesOps for LockedValues;
    using LockedValuesOps for GarbledLockedValues;

    function _signedPnlDelta(gtBool gtHasMadeProfit, gtInt256 gtProfitAmount, gtInt256 gtLossAmount) private returns (gtInt256) {
        gtInt256 gtZero = MpcCore.setPublic256(int256(0));
        return MpcCore.mux(gtHasMadeProfit, gtZero.checkedSub(gtLossAmount), gtProfitAmount);
    }

    function _storeLiquidationDeficit(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) private {
        LibEncryption.storeLiquidationDeficit(accountLayout, partyA, value);
    }

    function _storeLiquidationFee(AccountStorage.Layout storage accountLayout, address partyA, gtUint256 value) private {
        LibEncryption.storeLiquidationFee(accountLayout, partyA, value);
    }

    function _storeSettlementCva(
        AccountStorage.Layout storage accountLayout,
        address partyA,
        address partyB,
        gtUint256 value,
        address,
        address
    ) private {
        LibEncryption.storeSettlementCva(accountLayout, partyA, partyB, value);
    }

    function _storeSettlementActual(
        AccountStorage.Layout storage accountLayout,
        address partyA,
        address partyB,
        gtInt256 value,
        address,
        address
    ) private {
        LibEncryption.storeSettlementActual(accountLayout, partyA, partyB, value);
    }

    function _storeSettlementExpected(
        AccountStorage.Layout storage accountLayout,
        address partyA,
        address partyB,
        gtInt256 value,
        address,
        address
    ) private {
        LibEncryption.storeSettlementExpected(accountLayout, partyA, partyB, value);
    }

    function _copySettlementActualToExpected(AccountStorage.Layout storage accountLayout, address partyA, address partyB) private {
        accountLayout.settlementStates[partyA][partyB].expectedAmount = accountLayout.settlementStates[partyA][partyB].actualAmount;
        accountLayout.observerSettlementStates[partyA][partyB].expectedAmount = accountLayout.observerSettlementStates[partyA][partyB].actualAmount;
        accountLayout.partyBSettlementStates[partyA][partyB].expectedAmount = accountLayout.partyBSettlementStates[partyA][partyB].actualAmount;
    }

    function _initializeLiquidationAccumulator(AccountStorage.Layout storage accountLayout, address partyA) private {
        LibEncryption.storeIntForAddress(
            accountLayout.settlementStates[partyA][address(0)].actualAmount,
            accountLayout.observerSettlementStates[partyA][address(0)].actualAmount,
            MpcCore.setPublic256(int256(0)),
            LibAccount.getUserEncryptionAddress(partyA)
        );
    }

    function _updateLiquidationAccumulator(AccountStorage.Layout storage accountLayout, address partyA, address partyB) private {
        gtInt256 gtZero = MpcCore.setPublic256(int256(0));
        gtInt256 gtSettleAmount = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].expectedAmount.ciphertext);
        gtInt256 gtContribution;
        if (MpcCore.decrypt(gtSettleAmount.lt(gtZero))) {
            gtContribution = gtSettleAmount;
        } else {
            gtInt256 gtPartyBBalance = LibEncryption.toNonNegativeSigned(
                LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext)
            );
            gtContribution = MpcCore.decrypt(gtPartyBBalance.ge(gtSettleAmount)) ? gtSettleAmount : gtPartyBBalance;
        }
        gtInt256 gtCurrentAccumulated = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][address(0)].actualAmount.ciphertext);
        gtInt256 gtNewAccumulated = gtCurrentAccumulated.checkedAdd(gtContribution);
        LibEncryption.storeIntForAddress(
            accountLayout.settlementStates[partyA][address(0)].actualAmount,
            accountLayout.observerSettlementStates[partyA][address(0)].actualAmount,
            gtNewAccumulated,
            LibAccount.getUserEncryptionAddress(partyA)
        );
    }

    function _isLiquidationAccumulatorDisputed(AccountStorage.Layout storage accountLayout, address partyA) private returns (bool) {
        gtInt256 gtAccumulated = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][address(0)].actualAmount.ciphertext);
        gtInt256 gtExpectedUpnl = LockedValuesOps.safeOnboard(accountLayout.liquidationDetails[partyA].upnl.ciphertext);
        gtBool gtMatches = gtAccumulated.ge(gtExpectedUpnl).and(gtExpectedUpnl.ge(gtAccumulated));
        return !MpcCore.decrypt(gtMatches);
    }

    function liquidatePartyA(address partyA, LiquidationSig memory liquidationSig) internal {
        MAStorage.Layout storage maLayout = MAStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();

        LibMuonLiquidation.verifyLiquidationSig(liquidationSig, partyA);
        require(block.timestamp <= liquidationSig.timestamp + MuonStorage.layout().upnlValidTime, "LiquidationFacet: Expired signature");
        (gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) = LibOnChainUpnl.partyAUpnlAndLossFromSymbolPrices(partyA, liquidationSig.symbolIds, liquidationSig.prices);
        gtInt256 gtAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(gtUpnl, partyA);
        gtBool isInsolvent = MpcCore.lt(gtAvailableBalance, MpcCore.setPublic256(int256(0)));
        require(MpcCore.decrypt(isInsolvent), "LiquidationFacet: PartyA is solvent");
        address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
        maLayout.liquidationStatus[partyA] = true;
        accountLayout.liquidationDetails[partyA] = LiquidationDetail({
            liquidationId: liquidationSig.liquidationId,
            liquidationType: LiquidationType.NONE,
            upnl: LibEncryption.offBoardToUser(gtUpnl, partyAEncryptionAddress),
            totalUnrealizedLoss: LibEncryption.offBoardToUser(gtTotalUnrealizedLoss, partyAEncryptionAddress),
            deficit: 0,
            liquidationFee: 0,
            timestamp: liquidationSig.timestamp,
            involvedPartyBCounts: 0,
            partyAAccumulatedUpnl: 0,
            disputed: false,
            liquidationTimestamp: liquidationSig.timestamp
        });
        _initializeLiquidationAccumulator(accountLayout, partyA);
        accountLayout.liquidators[partyA].push(msg.sender);
    }

    function setSymbolsPrice(address partyA, LiquidationSig memory liquidationSig) internal {
        MAStorage.Layout storage maLayout = MAStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();

        LibMuonLiquidation.verifyLiquidationSig(liquidationSig, partyA);
        require(maLayout.liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        require(
            keccak256(accountLayout.liquidationDetails[partyA].liquidationId) == keccak256(liquidationSig.liquidationId),
            "LiquidationFacet: Invalid liquidationId"
        );
        for (uint256 index = 0; index < liquidationSig.symbolIds.length; index++) {
            accountLayout.symbolsPrices[partyA][liquidationSig.symbolIds[index]] = Price(
                liquidationSig.prices[index],
                accountLayout.liquidationDetails[partyA].timestamp
            );
        }

        (gtInt256 gtUpnl, gtInt256 gtTotalUnrealizedLoss) = LibOnChainUpnl.partyAUpnlAndLossFromSymbolPrices(partyA, liquidationSig.symbolIds, liquidationSig.prices);
        gtInt256 gtAvailableBalance2 = LibAccount.partyAAvailableBalanceForLiquidation(gtUpnl, partyA);
        accountLayout.liquidationDetails[partyA].totalUnrealizedLoss = LibEncryption.offBoardToUser(gtTotalUnrealizedLoss, LibAccount.getUserEncryptionAddress(partyA));
        if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.NONE) {
            gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].lf.ciphertext);
            gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
            gtUint256 gtDeficitMagnitude = MpcCore.setPublic256(int256(0)).checkedSub(gtAvailableBalance2).fromSigned();
            gtBool gtNormal = gtDeficitMagnitude.lt(gtLf);
            gtBool gtLate = gtDeficitMagnitude.le(gtLf.checkedAdd(gtCva));
            
            if (MpcCore.decrypt(gtNormal)) {
                accountLayout.liquidationDetails[partyA].liquidationType = LiquidationType.NORMAL;
                _storeLiquidationFee(accountLayout, partyA, gtLf.checkedSub(gtDeficitMagnitude));
            } else if (MpcCore.decrypt(gtLate)) {
                accountLayout.liquidationDetails[partyA].liquidationType = LiquidationType.LATE;
                _storeLiquidationDeficit(accountLayout, partyA, gtDeficitMagnitude.checkedSub(gtLf));
            } else {
                accountLayout.liquidationDetails[partyA].liquidationType = LiquidationType.OVERDUE;
                _storeLiquidationDeficit(accountLayout, partyA, gtDeficitMagnitude.checkedSub(gtLf).checkedSub(gtCva));
            }
            accountLayout.liquidators[partyA].push(msg.sender);
        }
    }

    function liquidatePendingPositionsPartyA(address partyA) internal returns (ctUint256[] memory liquidatedAmounts, bytes memory liquidationId) {
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();

        require(MAStorage.layout().liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        liquidatedAmounts = new ctUint256[](quoteLayout.partyAPendingQuotes[partyA].length);
        liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;
        address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
        for (uint256 index = 0; index < quoteLayout.partyAPendingQuotes[partyA].length; index++) {
            Quote storage quote = quoteLayout.quotes[quoteLayout.partyAPendingQuotes[partyA][index]];
            if (
                (quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING) &&
                quoteLayout.partyBPendingQuotes[quote.partyB][partyA].length > 0
            ) {
                delete quoteLayout.partyBPendingQuotes[quote.partyB][partyA];
                GarbledLockedValues memory gtZeroLockedB = LockedValuesOps.makeZero();
                LibEncryption.storePartyBPendingLockedBalance(accountLayout, quote.partyB, partyA, gtZeroLockedB);
            }
            gtUint256 gtFee = LibQuote.getTradingFee(quote.id);
            gtUint256 gtCurrentReimbursement = LibAccount.initializePartyAReimbursement(partyA);
            gtUint256 gtNewReimbursement = gtCurrentReimbursement.checkedAdd(gtFee);
            LibEncryption.storePartyAReimbursement(accountLayout, partyA, gtNewReimbursement);
            
            // Emit encrypted event
            ctUint256 memory ctFee = MpcCore.offBoardToUser(gtFee, partyAEncryptionAddress);
            emit SharedEvents.BalanceChangePartyA(partyA, ctFee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
            quote.quoteStatus = QuoteStatus.LIQUIDATED_PENDING;
            quote.statusModifyTimestamp = block.timestamp;
            
            // Onboard quantity for return array
            gtUint256 gtQuantityPending = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            liquidatedAmounts[index] = MpcCore.offBoardToUser(gtQuantityPending, partyAEncryptionAddress);
        }
        
        // Set pending locked balances to zero
        GarbledLockedValues memory gtZeroLockedA = LockedValuesOps.makeZero();
        LibEncryption.storePartyAPendingLockedBalance(accountLayout, partyA, gtZeroLockedA);
        delete quoteLayout.partyAPendingQuotes[partyA];
    }

    function liquidatePositionsPartyA(
        address partyA,
        uint256[] memory quoteIds
    ) internal returns (bool, ctUint256[] memory liquidatedAmounts, uint256[] memory closeIds, bytes memory liquidationId) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        MAStorage.Layout storage maLayout = MAStorage.layout();
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

        liquidatedAmounts = new ctUint256[](quoteIds.length);
        closeIds = new uint256[](quoteIds.length);
        liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;
        address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);

        require(maLayout.liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        for (uint256 index = 0; index < quoteIds.length; index++) {
            Quote storage quote = quoteLayout.quotes[quoteIds[index]];
            address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(quote.partyB);
            require(
                quote.quoteStatus == QuoteStatus.OPENED ||
                quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
                quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
                "LiquidationFacet: Invalid state"
            );
            require(!maLayout.partyBLiquidationStatus[quote.partyB][partyA], "LiquidationFacet: PartyB is in liquidation process");
            require(quote.partyA == partyA, "LiquidationFacet: Invalid party");
            require(
                accountLayout.symbolsPrices[partyA][quote.symbolId].timestamp == accountLayout.liquidationDetails[partyA].timestamp,
                "LiquidationFacet: Price should be set"
            );
            
            // Onboard quantity and closedAmount for liquidatedAmounts calculation
            gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            gtUint256 gtClosedAmount = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            ctUint256 memory ctLiquidatedAmount = MpcCore.offBoardToUser(gtQuantity.checkedSub(gtClosedAmount), partyAEncryptionAddress);
            liquidatedAmounts[index] = ctLiquidatedAmount;
            
            closeIds[index] = quoteLayout.closeIds[quote.id];
            quote.quoteStatus = QuoteStatus.LIQUIDATED;
            quote.statusModifyTimestamp = block.timestamp;

            accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;

            // Get open amount and convert price to encrypted
            gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
            gtUint256 gtPrice = MpcCore.setPublic256(accountLayout.symbolsPrices[partyA][quote.symbolId].price);
            
            (gtBool gtHasMadeProfit, gtUint256 gtAmount) = LibQuote.getValueOfQuoteForPartyA(
                gtPrice,
                gtOpenAmount,
                quote
            );

            if (!accountLayout.settlementStates[partyA][quote.partyB].pending) {
                accountLayout.settlementStates[partyA][quote.partyB].pending = true;
                accountLayout.liquidationDetails[partyA].involvedPartyBCounts += 1;
            }
            
            gtUint256 gtQuoteCva = LockedValuesOps.safeOnboard(quote.lockedValues.cva.ciphertext);
            gtUint256 gtDeficit = LockedValuesOps.safeOnboard(accountLayout.encryptedLiquidationDeficit[partyA].ciphertext);
            
            if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.NORMAL) {
                // Update cva with encrypted operations
                gtUint256 gtCurrentCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].cva.ciphertext);
                gtUint256 gtNewCva = gtCurrentCva.checkedAdd(gtQuoteCva);
                _storeSettlementCva(accountLayout, partyA, quote.partyB, gtNewCva, partyAEncryptionAddress, partyBEncryptionAddress);

                gtInt256 gtSignedAmount = LibEncryption.toNonNegativeSigned(gtAmount);
                gtInt256 gtAmountDelta = _signedPnlDelta(gtHasMadeProfit, gtSignedAmount, gtSignedAmount);
                gtInt256 gtCurrentActual = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                gtInt256 gtNewActual = gtCurrentActual.checkedAdd(gtAmountDelta);
                _storeSettlementActual(accountLayout, partyA, quote.partyB, gtNewActual, partyAEncryptionAddress, partyBEncryptionAddress);
                _copySettlementActualToExpected(accountLayout, partyA, quote.partyB);
            } else if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.LATE) {
                gtUint256 gtTotalCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
                // Zero total CVA ⇒ LATE only when deficit == LF (stored deficit 0); no CVA to haircut.
                gtUint256 gtAdjustedCva = MpcCore.decrypt(gtTotalCva.eq(MpcCore.setPublic256(uint256(0))))
                    ? gtQuoteCva
                    : gtQuoteCva.checkedSub(gtQuoteCva.checkedMul(gtDeficit).div(gtTotalCva));
                
                // Update cva with encrypted operations
                gtUint256 gtCurrentCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].cva.ciphertext);
                gtUint256 gtNewCva = gtCurrentCva.checkedAdd(gtAdjustedCva);
                _storeSettlementCva(accountLayout, partyA, quote.partyB, gtNewCva, partyAEncryptionAddress, partyBEncryptionAddress);
                
                gtInt256 gtSignedAmount = LibEncryption.toNonNegativeSigned(gtAmount);
                gtInt256 gtAmountDelta = _signedPnlDelta(gtHasMadeProfit, gtSignedAmount, gtSignedAmount);
                gtInt256 gtCurrentActual = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                gtInt256 gtNewActual = gtCurrentActual.checkedAdd(gtAmountDelta);
                _storeSettlementActual(accountLayout, partyA, quote.partyB, gtNewActual, partyAEncryptionAddress, partyBEncryptionAddress);
                _copySettlementActualToExpected(accountLayout, partyA, quote.partyB);
            } else if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.OVERDUE) {
                gtInt256 gtStoredTotalUnrealizedLoss = LockedValuesOps.safeOnboard(accountLayout.liquidationDetails[partyA].totalUnrealizedLoss.ciphertext);
                gtInt256 gtZero = MpcCore.setPublic256(int256(0));
                require(MpcCore.decrypt(gtStoredTotalUnrealizedLoss.lt(gtZero)), "LiquidationFacet: Invalid unrealized loss");
                gtUint256 gtTotalUnrealizedLoss = gtZero.checkedSub(gtStoredTotalUnrealizedLoss).fromSigned();
                gtInt256 gtSignedAmount = LibEncryption.toNonNegativeSigned(gtAmount);
                gtInt256 gtAdjustedAmount = LibEncryption.toNonNegativeSigned(
                    gtAmount.checkedSub(gtAmount.checkedMul(gtDeficit).div(gtTotalUnrealizedLoss))
                );
                gtInt256 gtActualDelta = _signedPnlDelta(gtHasMadeProfit, gtSignedAmount, gtAdjustedAmount);
                gtInt256 gtExpectedDelta = _signedPnlDelta(gtHasMadeProfit, gtSignedAmount, gtSignedAmount);

                gtInt256 gtCurrentActual = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                gtInt256 gtNewActual = gtCurrentActual.checkedAdd(gtActualDelta);
                _storeSettlementActual(accountLayout, partyA, quote.partyB, gtNewActual, partyAEncryptionAddress, partyBEncryptionAddress);

                gtInt256 gtCurrentExpected = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].expectedAmount.ciphertext);
                gtInt256 gtNewExpected = gtCurrentExpected.checkedAdd(gtExpectedDelta);
                _storeSettlementExpected(accountLayout, partyA, quote.partyB, gtNewExpected, partyAEncryptionAddress, partyBEncryptionAddress);
            }
            LibEncryption.storePartyBLockedBalance(
                accountLayout,
                quote.partyB,
                partyA,
                accountLayout.partyBLockedBalances[quote.partyB][partyA].subQuoteGarbled(quote)
            );
            
            // Calculate new avgClosedPrice with encrypted values
            gtUint256 gtAvgClosedPrice = LockedValuesOps.safeOnboard(quote.avgClosedPrice.ciphertext);
            gtUint256 gtClosedAmountForAvg = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            gtUint256 gtOpenAmountForAvg = gtOpenAmount; // Reuse from above
            gtUint256 gtLiquidationPrice = MpcCore.setPublic256(accountLayout.symbolsPrices[partyA][quote.symbolId].price);
            
            gtUint256 gtNewAvgClosedPrice = gtAvgClosedPrice.checkedMul(gtClosedAmountForAvg)
                .checkedAdd(gtOpenAmountForAvg.checkedMul(gtLiquidationPrice))
                .div(gtClosedAmountForAvg.checkedAdd(gtOpenAmountForAvg));
            LibEncryption.storeQuoteAvgClosedPrice(quoteLayout, quote, gtNewAvgClosedPrice);
            
            // Set closedAmount = quantity
            LibEncryption.storeQuoteClosedAmount(quoteLayout, quote, gtQuantity);

            LibQuote.removeFromOpenPositions(quote.id);
            quoteLayout.partyAPositionsCount[partyA] -= 1;
            quoteLayout.partyBPositionsCount[quote.partyB][partyA] -= 1;

            if (quoteLayout.partyBPositionsCount[quote.partyB][partyA] == 0) {
                _updateLiquidationAccumulator(accountLayout, partyA, quote.partyB);
            }
        }
        if (
            quoteLayout.partyAPositionsCount[partyA] == 0 &&
            _isLiquidationAccumulatorDisputed(accountLayout, partyA)
        ) {
            accountLayout.liquidationDetails[partyA].disputed = true;
            return (true, liquidatedAmounts, closeIds, liquidationId);
        }
        return (false, liquidatedAmounts, closeIds, liquidationId);
    }

    function resolveLiquidationDispute(
        address partyA,
        address[] memory partyBs,
        int256[] memory amounts,
        bool disputed
    ) internal returns (bytes memory) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);

        accountLayout.liquidationDetails[partyA].disputed = disputed;
        require(partyBs.length == amounts.length, "LiquidationFacet: Invalid length");
        for (uint256 i = 0; i < partyBs.length; i++) {
            address partyB = partyBs[i];
            address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
            gtInt256 gtAmount = MpcCore.setPublic256(amounts[i]);
            _storeSettlementActual(accountLayout, partyA, partyB, gtAmount, partyAEncryptionAddress, partyBEncryptionAddress);
        }
        return accountLayout.liquidationDetails[partyA].liquidationId;
    }

    function settlePartyALiquidation(
        address partyA,
        address[] memory partyBs
    ) internal returns (gtInt256[] memory settleAmounts, bytes memory liquidationId) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        require(
            quoteLayout.partyAPositionsCount[partyA] == 0 && quoteLayout.partyAPendingQuotes[partyA].length == 0,
            "LiquidationFacet: PartyA has still open positions"
        );
        require(MAStorage.layout().liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        require(!accountLayout.liquidationDetails[partyA].disputed, "LiquidationFacet: PartyA liquidation process get disputed");
        liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;
        address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);
        settleAmounts = new gtInt256[](partyBs.length);
        for (uint256 i = 0; i < partyBs.length; i++) {
            address partyB = partyBs[i];
            address partyBEncryptionAddress = LibAccount.getUserEncryptionAddress(partyB);
            require(accountLayout.settlementStates[partyA][partyB].pending, "LiquidationFacet: PartyB is not in settlement");
            accountLayout.settlementStates[partyA][partyB].pending = false;
            accountLayout.liquidationDetails[partyA].involvedPartyBCounts -= 1;

            // Convert ctInt256 to gtInt256 using MpcCore.onBoard
            gtInt256 gtSettleAmount = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].actualAmount.ciphertext);
            gtInt256 gtZero = MpcCore.setPublic256(int256(0));
            
            // Update partyB allocated balance with encrypted operations
            gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
            gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].cva.ciphertext);
            gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtCva);
            LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtNewBalance);
            
            // Emit encrypted event
            ctUint256 memory ctCva = MpcCore.offBoardToUser(gtCva, partyBEncryptionAddress);
            emit SharedEvents.BalanceChangePartyB(
                partyB,
                partyA,
                ctCva,
                SharedEvents.BalanceChangeType.CVA_IN
            );

            if (MpcCore.decrypt(gtSettleAmount.lt(gtZero))) {
                // Add positive amount to partyB balance
                gtUint256 gtCurrentBalance2 = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
                gtUint256 gtPositiveSettleAmount = gtSettleAmount.mul(MpcCore.setPublic256(int256(-1))).fromSigned();
                gtUint256 gtNewBalance2 = gtCurrentBalance2.checkedAdd(gtPositiveSettleAmount);
                LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtNewBalance2);
                
                // Emit encrypted event
                ctUint256 memory ctSettleAmount = MpcCore.offBoardToUser(gtPositiveSettleAmount, partyBEncryptionAddress);
                emit SharedEvents.BalanceChangePartyB(partyB, partyA, ctSettleAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
                settleAmounts[i] = gtSettleAmount;
            } else {
                gtUint256 gtCurrentBalance3 = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
                gtUint256 gtPositiveSettleAmount = gtSettleAmount.fromSigned();
                
                if (MpcCore.decrypt(gtCurrentBalance3.ge(gtPositiveSettleAmount))) {
                    gtUint256 gtNewBalance3 = gtCurrentBalance3.checkedSub(gtPositiveSettleAmount);
                    LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtNewBalance3);
                    
                    settleAmounts[i] = gtSettleAmount;
                    // Emit encrypted event
                    ctUint256 memory ctSettleAmount = MpcCore.offBoardToUser(gtPositiveSettleAmount, partyBEncryptionAddress);
                    emit SharedEvents.BalanceChangePartyB(partyB, partyA, ctSettleAmount, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
                } else {
                    settleAmounts[i] = LibEncryption.toNonNegativeSigned(gtCurrentBalance3);
                    LibEncryption.storePartyBAllocatedBalance(accountLayout, partyB, partyA, gtZero.fromSigned());
                    
                    // Emit encrypted event
                    ctUint256 memory ctSettleAmountsI = MpcCore.offBoardToUser(gtCurrentBalance3, partyBEncryptionAddress);
                    emit SharedEvents.BalanceChangePartyB(partyB, partyA, ctSettleAmountsI, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
                }
            }
            delete accountLayout.settlementStates[partyA][partyB];
            delete accountLayout.observerSettlementStates[partyA][partyB];
            delete accountLayout.partyBSettlementStates[partyA][partyB];
        }
        if (accountLayout.liquidationDetails[partyA].involvedPartyBCounts == 0) {
            // Prepare allocated balance for event emission
            gtUint256 gtAllocatedBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
            
            // Emit encrypted event
            ctUint256 memory ctAllocatedBalance = MpcCore.offBoardToUser(gtAllocatedBalance, partyAEncryptionAddress);
            emit SharedEvents.BalanceChangePartyA(partyA, ctAllocatedBalance, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
            
            // Set allocated balance to encrypted reimbursement amount.
            gtUint256 gtReimbursement = LibAccount.initializePartyAReimbursement(partyA);
            LibEncryption.storePartyAAllocatedBalance(accountLayout, partyA, gtReimbursement);
            accountLayout.partyAReimbursement[partyA] = 0;
            LibEncryption.storePartyAReimbursement(accountLayout, partyA, MpcCore.setPublic256(uint256(0)));
            // Set locked balances to zero
            GarbledLockedValues memory gtZeroLocked = LockedValuesOps.makeZero();
            LibEncryption.storePartyALockedBalance(accountLayout, partyA, gtZeroLocked);

            if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.NORMAL) {
                address liquidatorEncryptionAddress1 = LibAccount.getUserEncryptionAddress(accountLayout.liquidators[partyA][0]);
                address liquidatorEncryptionAddress2 = LibAccount.getUserEncryptionAddress(accountLayout.liquidators[partyA][1]);
                // Update liquidator balances with encrypted operations
                gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.encryptedLiquidationFee[partyA].ciphertext);
                gtUint256 gtCurrentBalance1 = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[accountLayout.liquidators[partyA][0]].ciphertext);
                gtUint256 gtLf1 = gtLf.div(MpcCore.setPublic256(uint256(2)));
                gtUint256 gtNewBalance1 = gtCurrentBalance1.checkedAdd(gtLf1);
                LibEncryption.storePartyAAllocatedBalance(accountLayout, accountLayout.liquidators[partyA][0], gtNewBalance1);
                
                gtUint256 gtCurrentBalance2 = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[accountLayout.liquidators[partyA][1]].ciphertext);
                gtUint256 gtLf2 = gtLf.div(MpcCore.setPublic256(uint256(2)));
                gtUint256 gtNewBalance2 = gtCurrentBalance2.checkedAdd(gtLf2);
                LibEncryption.storePartyAAllocatedBalance(accountLayout, accountLayout.liquidators[partyA][1], gtNewBalance2);
                
                // Emit encrypted events
                ctUint256 memory ctLf1 = MpcCore.offBoardToUser(gtLf1, liquidatorEncryptionAddress1);
                ctUint256 memory ctLf2 = MpcCore.offBoardToUser(gtLf2, liquidatorEncryptionAddress2);
                emit SharedEvents.BalanceChangePartyA(accountLayout.liquidators[partyA][0], ctLf1, SharedEvents.BalanceChangeType.LF_IN);
                emit SharedEvents.BalanceChangePartyA(accountLayout.liquidators[partyA][1], ctLf2, SharedEvents.BalanceChangeType.LF_IN);
            }
            delete accountLayout.liquidators[partyA];
            delete accountLayout.settlementStates[partyA][address(0)];
            delete accountLayout.encryptedLiquidationDeficit[partyA];
            delete accountLayout.observerEncryptedLiquidationDeficit[partyA];
            delete accountLayout.encryptedLiquidationFee[partyA];
            delete accountLayout.observerEncryptedLiquidationFee[partyA];
            delete accountLayout.liquidationDetails[partyA].liquidationType;
            MAStorage.layout().liquidationStatus[partyA] = false;
            accountLayout.partyANonces[partyA] += 1;
        }
    }

    function liquidatePartyB(address partyB, address partyA, SingleUpnlSig memory upnlSig) internal {
        LibMuonLiquidation.verifyPartyBUpnl(upnlSig, partyB, partyA);
        gtInt256 gtUpnl = LibOnChainUpnl.partyBUpnlFromQuotePrices(partyB, partyA, LibOnChainUpnl.priceSigFromSingle(upnlSig));
        LibLiquidation.liquidatePartyB(partyB, partyA, gtUpnl, upnlSig.timestamp);
    }

    function liquidatePositionsPartyB(
        address partyB,
        address partyA,
        QuotePriceSig memory priceSig
    ) internal returns (ctUint256[] memory liquidatedAmounts, uint256[] memory closeIds) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        MAStorage.Layout storage maLayout = MAStorage.layout();
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

        LibMuonLiquidation.verifyQuotePrices(priceSig);
        require(
            priceSig.timestamp <= maLayout.partyBLiquidationTimestamp[partyB][partyA] + maLayout.liquidationTimeout,
            "LiquidationFacet: Invalid signature"
        );
        require(maLayout.partyBLiquidationStatus[partyB][partyA], "LiquidationFacet: PartyB is solvent");
        require(maLayout.partyBLiquidationTimestamp[partyB][partyA] <= priceSig.timestamp, "LiquidationFacet: Expired signature");

        liquidatedAmounts = new ctUint256[](priceSig.quoteIds.length);
        closeIds = new uint256[](priceSig.quoteIds.length);
        address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(partyA);

        for (uint256 index = 0; index < priceSig.quoteIds.length; index++) {
            Quote storage quote = quoteLayout.quotes[priceSig.quoteIds[index]];
            require(
                quote.quoteStatus == QuoteStatus.OPENED ||
                quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
                quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
                "LiquidationFacet: Invalid state"
            );
            require(quote.partyA == partyA && quote.partyB == partyB, "LiquidationFacet: Invalid party");

            // Onboard quantity and closedAmount for liquidatedAmounts calculation
            gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            gtUint256 gtClosedAmount = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            liquidatedAmounts[index] = MpcCore.offBoardToUser(gtQuantity.checkedSub(gtClosedAmount), partyAEncryptionAddress);
            
            closeIds[index] = quoteLayout.closeIds[quote.id];
            quote.quoteStatus = QuoteStatus.LIQUIDATED;
            quote.statusModifyTimestamp = block.timestamp;

            LibEncryption.storePartyALockedBalance(accountLayout, partyA, accountLayout.lockedBalances[partyA].subQuoteGarbled(quote));

            // Calculate new avgClosedPrice with encrypted values
            gtUint256 gtAvgClosedPriceB = LockedValuesOps.safeOnboard(quote.avgClosedPrice.ciphertext);
            gtUint256 gtClosedAmountB = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            gtUint256 gtOpenAmountB = LibQuote.quoteOpenAmount(quote);
            gtUint256 gtPriceB = MpcCore.setPublic256(priceSig.prices[index]);
            
            gtUint256 gtNewAvgClosedPriceB = gtAvgClosedPriceB.checkedMul(gtClosedAmountB)
                .checkedAdd(gtOpenAmountB.checkedMul(gtPriceB))
                .div(gtClosedAmountB.checkedAdd(gtOpenAmountB));
            LibEncryption.storeQuoteAvgClosedPrice(quoteLayout, quote, gtNewAvgClosedPriceB);
            
            // Set closedAmount = quantity
            gtUint256 gtQuantityB = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            LibEncryption.storeQuoteClosedAmount(quoteLayout, quote, gtQuantityB);

            LibQuote.removeFromOpenPositions(quote.id);
            quoteLayout.partyAPositionsCount[partyA] -= 1;
            quoteLayout.partyBPositionsCount[partyB][partyA] -= 1;
        }
        gtUint256 gtPerPositionLiquidatorShare = LockedValuesOps.safeOnboard(maLayout.encryptedPartyBPositionLiquidatorsShare[partyB][partyA]);
        if (MpcCore.decrypt(gtPerPositionLiquidatorShare.gt(MpcCore.setPublic256(uint256(0))))) {
            gtUint256 gtLf = gtPerPositionLiquidatorShare.checkedMul(MpcCore.setPublic256(priceSig.quoteIds.length));

            address liquidatorEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
            // Update liquidator balance with encrypted operations
            gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[msg.sender].ciphertext);
            gtUint256 gtNewBalance = gtCurrentBalance.checkedAdd(gtLf);
            LibEncryption.storePartyAAllocatedBalance(accountLayout, msg.sender, gtNewBalance);
            
            // Emit encrypted event
            ctUint256 memory ctLf = MpcCore.offBoardToUser(gtLf, liquidatorEncryptionAddress);
            emit SharedEvents.BalanceChangePartyA(msg.sender, ctLf, SharedEvents.BalanceChangeType.LF_IN);
        }

        if (quoteLayout.partyBPositionsCount[partyB][partyA] == 0) {
            maLayout.partyBLiquidationStatus[partyB][partyA] = false;
            maLayout.partyBLiquidationTimestamp[partyB][partyA] = 0;
            maLayout.partyBPositionLiquidatorsShare[partyB][partyA] = 0;
            delete maLayout.encryptedPartyBPositionLiquidatorsShare[partyB][partyA];
            accountLayout.partyBNonces[partyB][partyA] += 1;
        }
        return (liquidatedAmounts, closeIds);
    }
}
