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

    function liquidatePartyA(address partyA, LiquidationSig memory liquidationSig) internal {
        MAStorage.Layout storage maLayout = MAStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();

        LibMuonLiquidation.verifyLiquidationSig(liquidationSig, partyA);
        require(block.timestamp <= liquidationSig.timestamp + MuonStorage.layout().upnlValidTime, "LiquidationFacet: Expired signature");
        gtInt256 gtAvailableBalance = LibAccount.partyAAvailableBalanceForLiquidation(
            liquidationSig.upnl,
            partyA
        );
        int256 availableBalance = MpcCore.decrypt(gtAvailableBalance);
        require(availableBalance < 0, "LiquidationFacet: PartyA is solvent");
        maLayout.liquidationStatus[partyA] = true;
        accountLayout.liquidationDetails[partyA] = LiquidationDetail({
            liquidationId: liquidationSig.liquidationId,
            liquidationType: LiquidationType.NONE,
            upnl: liquidationSig.upnl,
            totalUnrealizedLoss: liquidationSig.totalUnrealizedLoss,
            deficit: 0,
            liquidationFee: 0,
            timestamp: liquidationSig.timestamp,
            involvedPartyBCounts: 0,
            partyAAccumulatedUpnl: 0,
            disputed: false,
            liquidationTimestamp: liquidationSig.timestamp
        });
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

        gtInt256 gtAvailableBalance2 = LibAccount.partyAAvailableBalanceForLiquidation(
            liquidationSig.upnl,
            partyA
        );
        int256 availableBalance = MpcCore.decrypt(gtAvailableBalance2);
        
        if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.NONE) {
            // Decrypt lf and cva for liquidation type determination
            gtUint256 gtLf = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].lf.ciphertext);
            gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
            uint256 lf = MpcCore.decrypt(gtLf);
            uint256 cva = MpcCore.decrypt(gtCva);
            
            if (uint256(-availableBalance) < lf) {
                uint256 remainingLf = lf - uint256(-availableBalance);
                accountLayout.liquidationDetails[partyA].liquidationType = LiquidationType.NORMAL;
                accountLayout.liquidationDetails[partyA].liquidationFee = remainingLf;
            } else if (uint256(-availableBalance) <= lf + cva) {
                uint256 deficit = uint256(-availableBalance) - lf;
                accountLayout.liquidationDetails[partyA].liquidationType = LiquidationType.LATE;
                accountLayout.liquidationDetails[partyA].deficit = deficit;
            } else {
                uint256 deficit = uint256(-availableBalance) - lf - cva;
                accountLayout.liquidationDetails[partyA].liquidationType = LiquidationType.OVERDUE;
                accountLayout.liquidationDetails[partyA].deficit = deficit;
            }
            accountLayout.liquidators[partyA].push(msg.sender);
        }
    }

    function liquidatePendingPositionsPartyA(address partyA) internal returns (uint256[] memory liquidatedAmounts, bytes memory liquidationId) {
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();

        require(MAStorage.layout().liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        liquidatedAmounts = new uint256[](quoteLayout.partyAPendingQuotes[partyA].length);
        liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;
        for (uint256 index = 0; index < quoteLayout.partyAPendingQuotes[partyA].length; index++) {
            Quote storage quote = quoteLayout.quotes[quoteLayout.partyAPendingQuotes[partyA][index]];
            if (
                (quote.quoteStatus == QuoteStatus.LOCKED || quote.quoteStatus == QuoteStatus.CANCEL_PENDING) &&
                quoteLayout.partyBPendingQuotes[quote.partyB][partyA].length > 0
            ) {
                delete quoteLayout.partyBPendingQuotes[quote.partyB][partyA];
                GarbledLockedValues memory gtZeroLockedB = LockedValuesOps.makeZero();
                accountLayout.partyBPendingLockedBalances[quote.partyB][partyA] = gtZeroLockedB.offBoard(partyA);
            }
            gtUint256 gtFee = LibQuote.getTradingFee(quote.id);
            uint256 fee = MpcCore.decrypt(gtFee);
            accountLayout.partyAReimbursement[partyA] += fee;
            emit SharedEvents.BalanceChangePartyA(partyA, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
            quote.quoteStatus = QuoteStatus.LIQUIDATED_PENDING;
            quote.statusModifyTimestamp = block.timestamp;
            
            // Decrypt quantity for return array
            gtUint256 gtQuantityPending = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            liquidatedAmounts[index] = MpcCore.decrypt(gtQuantityPending);
        }
        
        // Set pending locked balances to zero
        GarbledLockedValues memory gtZeroLockedA = LockedValuesOps.makeZero();
        accountLayout.pendingLockedBalances[partyA] = gtZeroLockedA.offBoard(partyA);
        delete quoteLayout.partyAPendingQuotes[partyA];
    }

    function liquidatePositionsPartyA(
        address partyA,
        uint256[] memory quoteIds
    ) internal returns (bool, uint256[] memory liquidatedAmounts, uint256[] memory closeIds, bytes memory liquidationId) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        MAStorage.Layout storage maLayout = MAStorage.layout();
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();

        liquidatedAmounts = new uint256[](quoteIds.length);
        closeIds = new uint256[](quoteIds.length);
        liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;

        require(maLayout.liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        for (uint256 index = 0; index < quoteIds.length; index++) {
            Quote storage quote = quoteLayout.quotes[quoteIds[index]];
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
            
            // Decrypt quantity and closedAmount for liquidatedAmounts calculation
            gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            gtUint256 gtClosedAmount = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            liquidatedAmounts[index] = MpcCore.decrypt(gtQuantity.sub(gtClosedAmount));
            
            closeIds[index] = quoteLayout.closeIds[quote.id];
            quote.quoteStatus = QuoteStatus.LIQUIDATED;
            quote.statusModifyTimestamp = block.timestamp;

            accountLayout.partyBNonces[quote.partyB][quote.partyA] += 1;

            // Get open amount (decrypt for getValueOfQuoteForPartyA which takes plaintext)
            gtUint256 gtOpenAmount = LibQuote.quoteOpenAmount(quote);
            uint256 openAmount = MpcCore.decrypt(gtOpenAmount);
            
            (bool hasMadeProfit, gtUint256 gtAmount) = LibQuote.getValueOfQuoteForPartyA(
                accountLayout.symbolsPrices[partyA][quote.symbolId].price,
                openAmount,
                quote
            );
            uint256 amount = MpcCore.decrypt(gtAmount);

            if (!accountLayout.settlementStates[partyA][quote.partyB].pending) {
                accountLayout.settlementStates[partyA][quote.partyB].pending = true;
                accountLayout.liquidationDetails[partyA].involvedPartyBCounts += 1;
            }
            
            // Decrypt cva for settlement calculations
            gtUint256 gtQuoteCva = LockedValuesOps.safeOnboard(quote.lockedValues.cva.ciphertext);
            uint256 quoteCva = MpcCore.decrypt(gtQuoteCva);
            
            if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.NORMAL) {
                // Update cva with encrypted operations
                gtUint256 gtCurrentCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].cva.ciphertext);
                gtUint256 gtQuoteCva = MpcCore.setPublic256(quoteCva);
                gtUint256 gtNewCva = gtCurrentCva.add(gtQuoteCva);
                accountLayout.settlementStates[partyA][quote.partyB].cva = MpcCore.offBoardCombined(gtNewCva, partyA);

                if (hasMadeProfit) {
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentActual = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                    gtInt256 gtAmount = MpcCore.setPublic256(amount).toSigned();
                    gtInt256 gtNewActual = gtCurrentActual.add(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].actualAmount = MpcCore.offBoardCombined(gtNewActual, partyA);
                } else {
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentActual = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                    gtInt256 gtAmount = MpcCore.setPublic256(amount).toSigned();
                    gtInt256 gtNewActual = gtCurrentActual.sub(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].actualAmount = MpcCore.offBoardCombined(gtNewActual, partyA);
                }
                accountLayout.settlementStates[partyA][quote.partyB].expectedAmount = accountLayout
                    .settlementStates[partyA][quote.partyB].actualAmount;
            } else if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.LATE) {
                // Decrypt total cva for proportional calculation
                gtUint256 gtTotalCva = LockedValuesOps.safeOnboard(accountLayout.lockedBalances[partyA].cva.ciphertext);
                uint256 totalCva = MpcCore.decrypt(gtTotalCva);
                
                uint256 adjustedCva = quoteCva - ((quoteCva * accountLayout.liquidationDetails[partyA].deficit) / totalCva);
                
                // Update cva with encrypted operations
                gtUint256 gtCurrentCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][quote.partyB].cva.ciphertext);
                gtUint256 gtAdjustedCva = MpcCore.setPublic256(adjustedCva);
                gtUint256 gtNewCva = gtCurrentCva.add(gtAdjustedCva);
                accountLayout.settlementStates[partyA][quote.partyB].cva = MpcCore.offBoardCombined(gtNewCva, partyA);
                
                if (hasMadeProfit) {
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentActual = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                    gtInt256 gtAmount = MpcCore.setPublic256(amount).toSigned();
                    gtInt256 gtNewActual = gtCurrentActual.add(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].actualAmount = MpcCore.offBoardCombined(gtNewActual, partyA);
                } else {
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentActual = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                    gtInt256 gtAmount = MpcCore.setPublic256(amount).toSigned();
                    gtInt256 gtNewActual = gtCurrentActual.sub(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].actualAmount = MpcCore.offBoardCombined(gtNewActual, partyA);
                }
                accountLayout.settlementStates[partyA][quote.partyB].expectedAmount = accountLayout
                    .settlementStates[partyA][quote.partyB].actualAmount;
            } else if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.OVERDUE) {
                if (hasMadeProfit) {
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentActual = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                    gtInt256 gtAmount = MpcCore.setPublic256(amount).toSigned();
                    gtInt256 gtNewActual = gtCurrentActual.add(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].actualAmount = MpcCore.offBoardCombined(gtNewActual, partyA);
                    
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentExpected = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].expectedAmount.ciphertext);
                    gtInt256 gtNewExpected = gtCurrentExpected.add(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].expectedAmount = MpcCore.offBoardCombined(gtNewExpected, partyA);
                } else {
                    uint256 adjustedAmount = amount - ((amount * accountLayout.liquidationDetails[partyA].deficit) / uint256(-accountLayout.liquidationDetails[partyA].totalUnrealizedLoss));
                    
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentActual = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].actualAmount.ciphertext);
                    gtInt256 gtAdjustedAmount = MpcCore.setPublic256(adjustedAmount).toSigned();
                    gtInt256 gtNewActual = gtCurrentActual.sub(gtAdjustedAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].actualAmount = MpcCore.offBoardCombined(gtNewActual, partyA);
                    
                    // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                    gtInt256 gtCurrentExpected = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].expectedAmount.ciphertext);
                    gtInt256 gtAmount = MpcCore.setPublic256(amount).toSigned();
                    gtInt256 gtNewExpected = gtCurrentExpected.sub(gtAmount);
                    accountLayout.settlementStates[partyA][quote.partyB].expectedAmount = MpcCore.offBoardCombined(gtNewExpected, partyA);
                }
            }
            accountLayout.partyBLockedBalances[quote.partyB][partyA].subQuote(quote);
            
            // Calculate new avgClosedPrice with encrypted values
            gtUint256 gtAvgClosedPrice = LockedValuesOps.safeOnboard(quote.avgClosedPrice.ciphertext);
            gtUint256 gtClosedAmountForAvg = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            gtUint256 gtOpenAmountForAvg = gtOpenAmount; // Reuse from above
            gtUint256 gtLiquidationPrice = MpcCore.setPublic256(accountLayout.symbolsPrices[partyA][quote.symbolId].price);
            
            gtUint256 gtNewAvgClosedPrice = gtAvgClosedPrice.mul(gtClosedAmountForAvg)
                .add(gtOpenAmountForAvg.mul(gtLiquidationPrice))
                .div(gtClosedAmountForAvg.add(gtOpenAmountForAvg));
            quote.avgClosedPrice = gtNewAvgClosedPrice.offBoardCombined(quote.partyA);
            
            // Set closedAmount = quantity
            quote.closedAmount = gtQuantity.offBoardCombined(quote.partyA);

            LibQuote.removeFromOpenPositions(quote.id);
            quoteLayout.partyAPositionsCount[partyA] -= 1;
            quoteLayout.partyBPositionsCount[quote.partyB][partyA] -= 1;

            if (quoteLayout.partyBPositionsCount[quote.partyB][partyA] == 0) {
                // Convert ctInt256 to gtInt256 using MpcCore.onBoard
                gtInt256 gtSettleAmount = MpcCore.onBoard(accountLayout.settlementStates[partyA][quote.partyB].expectedAmount.ciphertext);
                int256 settleAmount = MpcCore.decrypt(gtSettleAmount);
                
                if (settleAmount < 0) {
                    accountLayout.liquidationDetails[partyA].partyAAccumulatedUpnl += settleAmount;
                } else {
                    gtUint256 gtPartyBBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[quote.partyB][partyA].ciphertext);
                    uint256 partyBBalance = MpcCore.decrypt(gtPartyBBalance);
                    
                    if (partyBBalance >= uint256(settleAmount)) {
                        accountLayout.liquidationDetails[partyA].partyAAccumulatedUpnl += settleAmount;
                    } else {
                        accountLayout.liquidationDetails[partyA].partyAAccumulatedUpnl += int256(partyBBalance);
                    }
                }
            }
        }
        if (
            quoteLayout.partyAPositionsCount[partyA] == 0 &&
            accountLayout.liquidationDetails[partyA].partyAAccumulatedUpnl != accountLayout.liquidationDetails[partyA].upnl
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

        accountLayout.liquidationDetails[partyA].disputed = disputed;
        require(partyBs.length == amounts.length, "LiquidationFacet: Invalid length");
        for (uint256 i = 0; i < partyBs.length; i++) {
            gtInt256 gtAmount = MpcCore.setPublic256(uint256(amounts[i])).toSigned();
            accountLayout.settlementStates[partyA][partyBs[i]].actualAmount = MpcCore.offBoardCombined(gtAmount, partyA);
        }
        return accountLayout.liquidationDetails[partyA].liquidationId;
    }

    function settlePartyALiquidation(
        address partyA,
        address[] memory partyBs
    ) internal returns (int256[] memory settleAmounts, bytes memory liquidationId) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
        require(
            quoteLayout.partyAPositionsCount[partyA] == 0 && quoteLayout.partyAPendingQuotes[partyA].length == 0,
            "LiquidationFacet: PartyA has still open positions"
        );
        require(MAStorage.layout().liquidationStatus[partyA], "LiquidationFacet: PartyA is solvent");
        require(!accountLayout.liquidationDetails[partyA].disputed, "LiquidationFacet: PartyA liquidation process get disputed");
        liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;
        settleAmounts = new int256[](partyBs.length);
        for (uint256 i = 0; i < partyBs.length; i++) {
            address partyB = partyBs[i];
            require(accountLayout.settlementStates[partyA][partyB].pending, "LiquidationFacet: PartyB is not in settlement");
            accountLayout.settlementStates[partyA][partyB].pending = false;
            accountLayout.liquidationDetails[partyA].involvedPartyBCounts -= 1;

            // Convert ctInt256 to gtInt256 using MpcCore.onBoard
            gtInt256 gtSettleAmount = MpcCore.onBoard(accountLayout.settlementStates[partyA][partyB].actualAmount.ciphertext);
            int256 settleAmount = MpcCore.decrypt(gtSettleAmount);
            
            // Update partyB allocated balance with encrypted operations
            gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
            gtUint256 gtCva = LockedValuesOps.safeOnboard(accountLayout.settlementStates[partyA][partyB].cva.ciphertext);
            gtUint256 gtNewBalance = gtCurrentBalance.add(gtCva);
            accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance, partyA);
            
            // Decrypt cva for event emission
            uint256 cva = MpcCore.decrypt(gtCva);
            emit SharedEvents.BalanceChangePartyB(
                partyB,
                partyA,
                cva,
                SharedEvents.BalanceChangeType.CVA_IN
            );

            if (settleAmount < 0) {
                // Add positive amount to partyB balance
                gtUint256 gtCurrentBalance2 = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
                gtUint256 gtSettleAmount = MpcCore.setPublic256(uint256(-settleAmount));
                gtUint256 gtNewBalance2 = gtCurrentBalance2.add(gtSettleAmount);
                accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance2, partyA);
                
                emit SharedEvents.BalanceChangePartyB(partyB, partyA, uint256(-settleAmount), SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
                settleAmounts[i] = settleAmount;
            } else {
                gtUint256 gtCurrentBalance3 = LockedValuesOps.safeOnboard(accountLayout.partyBAllocatedBalances[partyB][partyA].ciphertext);
                uint256 currentBalance = MpcCore.decrypt(gtCurrentBalance3);
                
                if (currentBalance >= uint256(settleAmount)) {
                    gtUint256 gtSettleAmount = MpcCore.setPublic256(uint256(settleAmount));
                    gtUint256 gtNewBalance3 = gtCurrentBalance3.sub(gtSettleAmount);
                    accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtNewBalance3, partyA);
                    
                    settleAmounts[i] = settleAmount;
                    emit SharedEvents.BalanceChangePartyB(partyB, partyA, uint256(settleAmount), SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
                } else {
                    settleAmounts[i] = int256(currentBalance);
                    gtUint256 gtZero = MpcCore.setPublic256(uint256(0));
                    accountLayout.partyBAllocatedBalances[partyB][partyA] = MpcCore.offBoardCombined(gtZero, partyA);
                    
                    emit SharedEvents.BalanceChangePartyB(partyB, partyA, uint256(settleAmounts[i]), SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
                }
            }
            delete accountLayout.settlementStates[partyA][partyB];
        }
        if (accountLayout.liquidationDetails[partyA].involvedPartyBCounts == 0) {
            // Decrypt allocated balance for event emission
            gtUint256 gtAllocatedBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[partyA].ciphertext);
            uint256 allocatedBalance = MpcCore.decrypt(gtAllocatedBalance);
            emit SharedEvents.BalanceChangePartyA(partyA, allocatedBalance, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
            
            // Set allocated balance to reimbursement amount
            gtUint256 gtReimbursement = MpcCore.setPublic256(accountLayout.partyAReimbursement[partyA]);
            accountLayout.allocatedBalances[partyA] = MpcCore.offBoardCombined(gtReimbursement, partyA);
            accountLayout.partyAReimbursement[partyA] = 0;
            // Set locked balances to zero
            GarbledLockedValues memory gtZeroLocked = LockedValuesOps.makeZero();
            accountLayout.lockedBalances[partyA] = gtZeroLocked.offBoard(partyA);

            uint256 lf = accountLayout.liquidationDetails[partyA].liquidationFee;
            if (lf > 0) {
                // Update liquidator balances with encrypted operations
                gtUint256 gtCurrentBalance1 = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[accountLayout.liquidators[partyA][0]].ciphertext);
                gtUint256 gtLf1 = MpcCore.setPublic256(lf / 2);
                gtUint256 gtNewBalance1 = gtCurrentBalance1.add(gtLf1);
                accountLayout.allocatedBalances[accountLayout.liquidators[partyA][0]] = MpcCore.offBoardCombined(gtNewBalance1, accountLayout.liquidators[partyA][0]);
                
                gtUint256 gtCurrentBalance2 = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[accountLayout.liquidators[partyA][1]].ciphertext);
                gtUint256 gtLf2 = MpcCore.setPublic256(lf / 2);
                gtUint256 gtNewBalance2 = gtCurrentBalance2.add(gtLf2);
                accountLayout.allocatedBalances[accountLayout.liquidators[partyA][1]] = MpcCore.offBoardCombined(gtNewBalance2, accountLayout.liquidators[partyA][1]);
                
                emit SharedEvents.BalanceChangePartyA(accountLayout.liquidators[partyA][0], lf / 2, SharedEvents.BalanceChangeType.LF_IN);
                emit SharedEvents.BalanceChangePartyA(accountLayout.liquidators[partyA][1], lf / 2, SharedEvents.BalanceChangeType.LF_IN);
            }
            delete accountLayout.liquidators[partyA];
            delete accountLayout.liquidationDetails[partyA].liquidationType;
            MAStorage.layout().liquidationStatus[partyA] = false;
            accountLayout.partyANonces[partyA] += 1;
        }
    }

    function liquidatePartyB(address partyB, address partyA, SingleUpnlSig memory upnlSig) internal {
        LibMuonLiquidation.verifyPartyBUpnl(upnlSig, partyB, partyA);
        LibLiquidation.liquidatePartyB(partyB, partyA, upnlSig.upnl, upnlSig.timestamp);
    }

    function liquidatePositionsPartyB(
        address partyB,
        address partyA,
        QuotePriceSig memory priceSig
    ) internal returns (uint256[] memory liquidatedAmounts, uint256[] memory closeIds) {
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

        liquidatedAmounts = new uint256[](priceSig.quoteIds.length);
        closeIds = new uint256[](priceSig.quoteIds.length);

        for (uint256 index = 0; index < priceSig.quoteIds.length; index++) {
            Quote storage quote = quoteLayout.quotes[priceSig.quoteIds[index]];
            require(
                quote.quoteStatus == QuoteStatus.OPENED ||
                quote.quoteStatus == QuoteStatus.CLOSE_PENDING ||
                quote.quoteStatus == QuoteStatus.CANCEL_CLOSE_PENDING,
                "LiquidationFacet: Invalid state"
            );
            require(quote.partyA == partyA && quote.partyB == partyB, "LiquidationFacet: Invalid party");

            // Decrypt quantity and closedAmount for liquidatedAmounts calculation
            gtUint256 gtQuantity = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            gtUint256 gtClosedAmount = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            liquidatedAmounts[index] = MpcCore.decrypt(gtQuantity.sub(gtClosedAmount));
            
            closeIds[index] = quoteLayout.closeIds[quote.id];
            quote.quoteStatus = QuoteStatus.LIQUIDATED;
            quote.statusModifyTimestamp = block.timestamp;

            accountLayout.lockedBalances[partyA].subQuote(quote);

            // Calculate new avgClosedPrice with encrypted values
            gtUint256 gtAvgClosedPriceB = LockedValuesOps.safeOnboard(quote.avgClosedPrice.ciphertext);
            gtUint256 gtClosedAmountB = LockedValuesOps.safeOnboard(quote.closedAmount.ciphertext);
            gtUint256 gtOpenAmountB = LibQuote.quoteOpenAmount(quote);
            gtUint256 gtPriceB = MpcCore.setPublic256(priceSig.prices[index]);
            
            gtUint256 gtNewAvgClosedPriceB = gtAvgClosedPriceB.mul(gtClosedAmountB)
                .add(gtOpenAmountB.mul(gtPriceB))
                .div(gtClosedAmountB.add(gtOpenAmountB));
            quote.avgClosedPrice = gtNewAvgClosedPriceB.offBoardCombined(quote.partyA);
            
            // Set closedAmount = quantity
            gtUint256 gtQuantityB = LockedValuesOps.safeOnboard(quote.quantity.ciphertext);
            quote.closedAmount = gtQuantityB.offBoardCombined(quote.partyA);

            LibQuote.removeFromOpenPositions(quote.id);
            quoteLayout.partyAPositionsCount[partyA] -= 1;
            quoteLayout.partyBPositionsCount[partyB][partyA] -= 1;
        }
        if (maLayout.partyBPositionLiquidatorsShare[partyB][partyA] > 0) {
            uint256 lf = maLayout.partyBPositionLiquidatorsShare[partyB][partyA] * priceSig.quoteIds.length;
            
            // Update liquidator balance with encrypted operations
            gtUint256 gtCurrentBalance = LockedValuesOps.safeOnboard(accountLayout.allocatedBalances[msg.sender].ciphertext);
            gtUint256 gtLf = MpcCore.setPublic256(lf);
            gtUint256 gtNewBalance = gtCurrentBalance.add(gtLf);
            accountLayout.allocatedBalances[msg.sender] = MpcCore.offBoardCombined(gtNewBalance, msg.sender);
            
            emit SharedEvents.BalanceChangePartyA(msg.sender, lf, SharedEvents.BalanceChangeType.LF_IN);
        }

        if (quoteLayout.partyBPositionsCount[partyB][partyA] == 0) {
            maLayout.partyBLiquidationStatus[partyB][partyA] = false;
            maLayout.partyBLiquidationTimestamp[partyB][partyA] = 0;
            accountLayout.partyBNonces[partyB][partyA] += 1;
        }
        return (liquidatedAmounts, closeIds);
    }
}
