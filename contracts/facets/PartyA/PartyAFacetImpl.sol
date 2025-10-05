// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibLockedValues.sol";
import "../../libraries/muon/LibMuonPartyA.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibSolvency.sol";
import "../../libraries/LibQuote.sol";
import "../../libraries/LibLiquidation.sol";
import "../../libraries/LibAccessibility.sol";
import "../../libraries/SharedEvents.sol";
import "../../libraries/LibSettlement.sol";
import "../../storages/MAStorage.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library PartyAFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;

	using LockedValuesOps for LockedValues;
	using LockedValuesOps for GarbledLockedValues;

	function sendQuote(
		address[] memory partyBsWhiteList,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		gtUint256 gtPrice,
		gtUint256 gtQuantity,
		gtUint256 gtCva,
		gtUint256 gtLf,
		gtUint256 gtPartyAmm,
		gtUint256 gtPartyBmm,
		uint256 maxFundingRate,
		uint256 deadline,
		address affiliate,
		SingleUpnlAndPriceSig memory upnlSig
	) internal returns (uint256 currentId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

		require(!LibAccessibility.hasRole(msg.sender, LibAccessibility.LIQUIDATOR_ROLE), "PartyAFacet: Liquidator can't be partyA");
		require(
			quoteLayout.partyAPendingQuotes[msg.sender].length < maLayout.pendingQuotesValidLength,
			"PartyAFacet: Number of pending quotes out of range"
		);
		require(symbolLayout.symbols[symbolId].isValid, "PartyAFacet: Symbol is not valid");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");

		// Create private locked values struct
		GarbledLockedValues memory garbledLockedValues = GarbledLockedValues({
			cva: gtCva,
			lf: gtLf,
			partyAmm: gtPartyAmm,
			partyBmm: gtPartyBmm
		});

		// Calculate gt trading price based on order type
		gtUint256 gtTradingPrice = MpcCore.mux(
			MpcCore.eq(MpcCore.setPublic256(uint256(orderType)), MpcCore.setPublic256(uint256(OrderType.LIMIT))),
			gtPrice,
			MpcCore.setPublic256(upnlSig.price)
		);

		// Perform gt validations
		gtUint256 gtTotalForPartyA = garbledLockedValues.totalForPartyA();

		gtUint256 minLfRequired = gtTotalForPartyA.mul(MpcCore.setPublic256(symbolLayout.symbols[symbolId].minAcceptablePortionLF)).div(
			MpcCore.setPublic256(uint256(1e18))
		);
		gtBool lfSufficient = gtLf.ge(minLfRequired);

		// Check minimum quote value: totalForPartyA >= minAcceptableQuoteValue
		gtBool quoteSufficient = gtTotalForPartyA.ge(MpcCore.setPublic256(symbolLayout.symbols[symbolId].minAcceptableQuoteValue));

		// Calculate gt trading fee: (quantity * tradingPrice * tradingFee) / 1e36
		gtUint256 gtTradingFee = gtQuantity.mul(gtTradingPrice).mul(MpcCore.setPublic256(symbolLayout.symbols[symbolId].tradingFee)).div(
			MpcCore.setPublic256(uint256(1e36))
		);

		// Calculate total required balance: totalForPartyA + tradingFee
		gtUint256 totalRequired = gtTotalForPartyA.add(gtTradingFee);

		// Check available balance sufficiency using LibAccount
		gtInt256 gtAvailableBalance = LibAccount.partyAAvailableForQuote(upnlSig.upnl, msg.sender);
		gtBool balanceSufficient = totalRequired.toSigned().le(gtAvailableBalance);

		// Combine all validation results
		gtBool allValidationsPassed = lfSufficient.and(quoteSufficient).and(balanceSufficient);

		// Only decrypt the final validation result for require check
		bool allValidationsPassedDecrypted = MpcCore.decrypt(allValidationsPassed);
		require(MpcCore.decrypt(lfSufficient),"1");
		require(MpcCore.decrypt(quoteSufficient),"2");
		// require(MpcCore.decrypt(balanceSufficient),"3");
		// require(allValidationsPassedDecrypted, "PartyAFacet: Validation failed");

		// // Additional non-encrypted validations
		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			require(partyBsWhiteList[i] != msg.sender, "PartyAFacet: Sender isn't allowed in partyBWhiteList");
		}
		require(maLayout.affiliateStatus[affiliate] || affiliate == address(0), "PartyAFacet: Invalid affiliate");

		LibMuonPartyA.verifyPartyAUpnlAndPrice(upnlSig, msg.sender, symbolId);

		address partyAEncryptionAddress = LibAccount.getUserEncryptionAddress(msg.sender);
		// Add to pending locked balances in private storage
		accountLayout.pendingLockedBalances[msg.sender] = accountLayout
			.pendingLockedBalances[msg.sender]
			.onBoard()
			.add(garbledLockedValues)
			.offBoard(partyAEncryptionAddress);

		currentId = ++quoteLayout.lastId;

		// Create private quote
		Quote memory privateQuote = Quote({
			id: currentId,
			partyBsWhiteList: partyBsWhiteList,
			symbolId: symbolId,
			positionType: positionType,
			orderType: orderType,
			openedPrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			initialOpenedPrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			requestedOpenPrice: gtPrice.offBoardCombined(partyAEncryptionAddress),
			marketPrice: MpcCore.setPublic256(upnlSig.price).offBoardCombined(partyAEncryptionAddress),
			quantity: gtQuantity.offBoardCombined(partyAEncryptionAddress),
			closedAmount: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			lockedValues: garbledLockedValues.offBoard(partyAEncryptionAddress),
			initialLockedValues: garbledLockedValues.offBoard(partyAEncryptionAddress),
			maxFundingRate: maxFundingRate,
			partyA: MpcCore.setPublic256(uint256(uint160(msg.sender))).offBoardCombined(partyAEncryptionAddress),
			partyB: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			quoteStatus: QuoteStatus.PENDING,
			avgClosedPrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			requestedClosePrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			quantityToClose: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
			lastFundingPaymentTimestamp: 0,
			deadline: deadline,
			tradingFee: gtTradingFee.offBoardCombined(partyAEncryptionAddress),
			affiliate: affiliate
		});

		// Store quote and update indexes in private storage
		quoteLayout.quoteIdsOf[msg.sender].push(currentId);
		quoteLayout.partyAPendingQuotes[msg.sender].push(currentId);
		quoteLayout.quotes[currentId] = privateQuote;

		// Only decrypt trading fee when we need to deduct it from allocated balances
		uint256 fee = MpcCore.decrypt(gtTradingFee);
		accountLayout.allocatedBalances[msg.sender] -= fee;
		emit SharedEvents.BalanceChangePartyA(msg.sender, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_OUT);
	}

	function requestToCancelQuote(uint256 quoteId) internal returns (QuoteStatus result) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.PENDING || quote.quoteStatus == QuoteStatus.LOCKED, "PartyAFacet: Invalid state");

		if (block.timestamp > quote.deadline) {
			result = LibQuote.expireQuote(quoteId);
		} else if (quote.quoteStatus == QuoteStatus.PENDING) {
			quote.quoteStatus = QuoteStatus.CANCELED;
			uint256 fee = LibQuote.getTradingFee(quote.id);
			accountLayout.allocatedBalances[quote.partyA] += fee;
			emit SharedEvents.BalanceChangePartyA(quote.partyA, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
			accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
			LibQuote.removeFromPartyAPendingQuotes(quote);
			result = QuoteStatus.CANCELED;
		} else {
			// Quote is locked
			quote.quoteStatus = QuoteStatus.CANCEL_PENDING;
			result = QuoteStatus.CANCEL_PENDING;
		}
		quote.statusModifyTimestamp = block.timestamp;
	}

	function requestToClosePosition(uint256 quoteId, uint256 closePrice, uint256 quantityToClose, OrderType orderType, uint256 deadline) internal {
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.OPENED, "PartyAFacet: Invalid state");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
		require(LibQuote.quoteOpenAmount(quote) >= quantityToClose, "PartyAFacet: Invalid quantityToClose");

		// check that remaining position is not too small
		if (LibQuote.quoteOpenAmount(quote) > quantityToClose) {
			require(
				((LibQuote.quoteOpenAmount(quote) - quantityToClose) * quote.lockedValues.totalForPartyA()) / LibQuote.quoteOpenAmount(quote) >=
					symbolLayout.symbols[quote.symbolId].minAcceptableQuoteValue,
				"PartyAFacet: Remaining quote value is low"
			);
		}
		quoteLayout.closeIds[quoteId] = ++quoteLayout.lastCloseId;
		quote.statusModifyTimestamp = block.timestamp;
		quote.quoteStatus = QuoteStatus.CLOSE_PENDING;
		quote.requestedClosePrice = closePrice;
		quote.quantityToClose = quantityToClose;
		quote.orderType = orderType;
		quote.deadline = deadline;
	}

	function requestToCancelCloseRequest(uint256 quoteId) internal returns (QuoteStatus) {
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.CLOSE_PENDING, "PartyAFacet: Invalid state");
		if (block.timestamp > quote.deadline) {
			LibQuote.expireQuote(quoteId);
			return QuoteStatus.OPENED;
		} else {
			quote.statusModifyTimestamp = block.timestamp;
			quote.quoteStatus = QuoteStatus.CANCEL_CLOSE_PENDING;
			return QuoteStatus.CANCEL_CLOSE_PENDING;
		}
	}
}
