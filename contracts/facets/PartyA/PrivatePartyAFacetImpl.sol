// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
// import "../../libraries/LibLockedValues.sol";
import "../../libraries/LibLockedPrivateValues.sol";
import "../../libraries/muon/LibMuonPartyA.sol";
import "../../libraries/LibSolvency.sol"; // replace with a private version (uses PrivateQuoteStorage)
import "../../libraries/LibAccessibility.sol";
import "../../libraries/SharedEvents.sol";
import "../../libraries/LibSettlement.sol";
import "../../storages/MAStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../libraries/LibPrivateQuote.sol";
import "../../libraries/LibPrivateAccount.sol";

library PrivatePartyAFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtInt256;
	using MpcCore for gtBool;
	using LockedPrivateValuesOps for PrivateLockedValues;
	using LockedPrivateValuesOps for GarbledPrivateLockedValues;

	function sendPrivateQuote(
		address[] memory partyBsWhiteList,
		uint256 symbolId,
		PrivatePositionType positionType,
		PrivateOrderType orderType,
		gtUint256 memory gtPrice,
		gtUint256 memory gtQuantity,
		gtUint256 memory gtCva,
		gtUint256 memory gtLf,
		gtUint256 memory gtPartyAmm,
		gtUint256 memory gtPartyBmm,
		uint256 maxFundingRate,
		uint256 deadline,
		address affiliate,
		SingleUpnlAndPriceSig memory upnlSig
	) internal returns (uint256 currentId) {
		PrivateQuoteStorage.Layout storage privateQuoteLayout = PrivateQuoteStorage.layout();
		PrivateAccountStorage.Layout storage privateAccountLayout = PrivateAccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

		require(!LibAccessibility.hasRole(msg.sender, LibAccessibility.LIQUIDATOR_ROLE), "PrivatePartyAFacet: Liquidator can't be partyA");
		require(
			privateQuoteLayout.partyAPendingQuotes[msg.sender].length < maLayout.pendingQuotesValidLength,
			"PrivatePartyAFacet: Number of pending quotes out of range"
		);
		require(symbolLayout.symbols[symbolId].isValid, "PrivatePartyAFacet: Symbol is not valid");
		require(deadline >= block.timestamp, "PrivatePartyAFacet: Low deadline");

		// Create private locked values struct
		GarbledPrivateLockedValues memory garbledPrivateLockedValues = GarbledPrivateLockedValues({
			cva: gtCva,
			lf: gtLf,
			partyAmm: gtPartyAmm,
			partyBmm: gtPartyBmm
		});

		// Calculate gt trading price based on order type
		gtUint256 memory gtTradingPrice = MpcCore.mux(
			MpcCore.eq(MpcCore.setPublic256(uint256(orderType)), MpcCore.setPublic256(uint256(OrderType.LIMIT))),
			gtPrice,
			MpcCore.setPublic256(upnlSig.price)
		);

		// Perform gt validations
		gtUint256 memory gtTotalForPartyA = LockedPrivateValuesOps.totalForPartyA(garbledPrivateLockedValues);

		// Check minimum LF requirement: lf >= (minAcceptablePortionLF * totalForPartyA) / 1e18
		gtUint256 memory minAcceptablePortionLF = MpcCore.setPublic256(symbolLayout.symbols[symbolId].minAcceptablePortionLF);
		return gtTotalForPartyA.decrypt();
		// gtUint256 memory minLfRequiredMul = gtTotalForPartyA.mul(minAcceptablePortionLF);
		// gtUint256 memory minLfRequiredDiv = minLfRequiredMul.div(MpcCore.setPublic256(uint256(1e18)));
		// gtBool lfSufficient = gtLf.ge(minLfRequiredDiv);

		// // Check minimum quote value: totalForPartyA >= minAcceptableQuoteValue
		// gtBool quoteSufficient = gtTotalForPartyA.ge(MpcCore.setPublic256(symbolLayout.symbols[symbolId].minAcceptableQuoteValue));

		// // Calculate gt trading fee: (quantity * tradingPrice * tradingFee) / 1e36
		// gtUint256 memory gtTradingFee = gtQuantity.mul(gtTradingPrice).mul(MpcCore.setPublic256(symbolLayout.symbols[symbolId].tradingFee)).div(
		// 	MpcCore.setPublic256(uint256(1e36))
		// );

		// // Calculate total required balance: totalForPartyA + tradingFee
		// gtUint256 memory totalRequired = gtTotalForPartyA.add(gtTradingFee);

		// // Check available balance sufficiency using LibPrivateAccount
		// gtInt256 memory gtAvailableBalance = LibPrivateAccount.partyAAvailableForQuote(upnlSig.upnl, msg.sender);
		// gtBool balanceSufficient = totalRequired.toSigned().le(gtAvailableBalance);

		// // Combine all validation results
		// gtBool allValidationsPassed = lfSufficient.and(quoteSufficient).and(balanceSufficient);

		// // Only decrypt the final validation result for require check
		// require(MpcCore.decrypt(allValidationsPassed), "PrivatePartyAFacet: Validation failed");

		// // Additional non-encrypted validations
		// for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
		// 	require(partyBsWhiteList[i] != msg.sender, "PrivatePartyAFacet: Sender isn't allowed in partyBWhiteList");
		// }
		// require(maLayout.affiliateStatus[affiliate] || affiliate == address(0), "PrivatePartyAFacet: Invalid affiliate");

		// LibMuonPartyA.verifyPartyAUpnlAndPrice(upnlSig, msg.sender, symbolId);

		// address partyAEncryptionAddress = LibPrivateAccount.getUserEncryptionAddress(msg.sender);
		// // Add to pending locked balances in private storage
		// privateAccountLayout.encryptedPendingLockedBalances[msg.sender] = privateAccountLayout
		// 	.encryptedPendingLockedBalances[msg.sender]
		// 	.onBoard()
		// 	.add(garbledPrivateLockedValues)
		// 	.offBoard(partyAEncryptionAddress);

		// currentId = ++privateQuoteLayout.lastId;

		// // Create private quote
		// PrivateQuote memory privateQuote = PrivateQuote({
		// 	id: currentId,
		// 	partyBsWhiteList: partyBsWhiteList,
		// 	symbolId: symbolId,
		// 	positionType: positionType,
		// 	orderType: orderType,
		// 	openedPrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	initialOpenedPrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	requestedOpenPrice: gtPrice.offBoardCombined(partyAEncryptionAddress),
		// 	marketPrice: MpcCore.setPublic256(upnlSig.price).offBoardCombined(partyAEncryptionAddress),
		// 	quantity: gtQuantity.offBoardCombined(partyAEncryptionAddress),
		// 	closedAmount: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	lockedValues: garbledPrivateLockedValues.offBoard(partyAEncryptionAddress),
		// 	initialLockedValues: garbledPrivateLockedValues.offBoard(partyAEncryptionAddress),
		// 	maxFundingRate: maxFundingRate,
		// 	partyA: MpcCore.setPublic256(uint256(uint160(msg.sender))).offBoardCombined(partyAEncryptionAddress),
		// 	partyB: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	quoteStatus: PrivateQuoteStatus.PENDING,
		// 	avgClosedPrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	requestedClosePrice: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	parentId: 0,
		// 	createTimestamp: block.timestamp,
		// 	statusModifyTimestamp: block.timestamp,
		// 	quantityToClose: MpcCore.setPublic256(uint256(0)).offBoardCombined(partyAEncryptionAddress),
		// 	lastFundingPaymentTimestamp: 0,
		// 	deadline: deadline,
		// 	tradingFee: gtTradingFee.offBoardCombined(partyAEncryptionAddress),
		// 	affiliate: affiliate
		// });

		// // Store quote and update indexes in private storage
		// privateQuoteLayout.quoteIdsOf[msg.sender].push(currentId);
		// privateQuoteLayout.partyAPendingQuotes[msg.sender].push(currentId);
		// privateQuoteLayout.quotes[currentId] = privateQuote;

		// // Only decrypt trading fee when we need to deduct it from allocated balances
		// uint256 fee = MpcCore.decrypt(gtTradingFee);
		// privateAccountLayout.allocatedBalances[msg.sender] -= fee;
		// emit SharedEvents.BalanceChangePartyA(msg.sender, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_OUT);
	}

	// function requestToCancelQuote(uint256 quoteId) internal returns (QuoteStatus result) {
	// 	AccountStorage.Layout storage accountLayout = AccountStorage.layout();
	// 	Quote storage quote = QuoteStorage.layout().quotes[quoteId];

	// 	require(quote.quoteStatus == QuoteStatus.PENDING || quote.quoteStatus == QuoteStatus.LOCKED, "PrivatePartyAFacet: Invalid state");

	// 	if (block.timestamp > quote.deadline) {
	// 		result = LibQuote.expireQuote(quoteId);
	// 	} else if (quote.quoteStatus == QuoteStatus.PENDING) {
	// 		quote.quoteStatus = QuoteStatus.CANCELED;
	// 		uint256 fee = LibQuote.getTradingFee(quote.id);
	// 		accountLayout.allocatedBalances[quote.partyA] += fee;
	// 		emit SharedEvents.BalanceChangePartyA(quote.partyA, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_IN);
	// 		accountLayout.pendingLockedBalances[quote.partyA].subQuote(quote);
	// 		LibQuote.removeFromPartyAPendingQuotes(quote);
	// 		result = QuoteStatus.CANCELED;
	// 	} else {
	// 		// Quote is locked
	// 		quote.quoteStatus = QuoteStatus.CANCEL_PENDING;
	// 		result = QuoteStatus.CANCEL_PENDING;
	// 	}
	// 	quote.statusModifyTimestamp = block.timestamp;
	// }

	// function requestToClosePosition(uint256 quoteId, uint256 closePrice, uint256 quantityToClose, OrderType orderType, uint256 deadline) internal {
	// 	SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
	// 	QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
	// 	Quote storage quote = quoteLayout.quotes[quoteId];

	// 	require(quote.quoteStatus == QuoteStatus.OPENED, "PrivatePartyAFacet: Invalid state");
	// 	require(deadline >= block.timestamp, "PrivatePartyAFacet: Low deadline");
	// 	require(LibQuote.quoteOpenAmount(quote) >= quantityToClose, "PrivatePartyAFacet: Invalid quantityToClose");

	// 	// check that remaining position is not too small
	// 	if (LibQuote.quoteOpenAmount(quote) > quantityToClose) {
	// 		require(
	// 			((LibQuote.quoteOpenAmount(quote) - quantityToClose) * quote.lockedValues.totalForPartyA()) / LibQuote.quoteOpenAmount(quote) >=
	// 				symbolLayout.symbols[quote.symbolId].minAcceptableQuoteValue,
	// 			"PrivatePartyAFacet: Remaining quote value is low"
	// 		);
	// 	}
	// 	quoteLayout.closeIds[quoteId] = ++quoteLayout.lastCloseId;
	// 	quote.statusModifyTimestamp = block.timestamp;
	// 	quote.quoteStatus = QuoteStatus.CLOSE_PENDING;
	// 	quote.requestedClosePrice = closePrice;
	// 	quote.quantityToClose = quantityToClose;
	// 	quote.orderType = orderType;
	// 	quote.deadline = deadline;
	// }

	// function requestToCancelCloseRequest(uint256 quoteId) internal returns (QuoteStatus) {
	// 	Quote storage quote = QuoteStorage.layout().quotes[quoteId];

	// 	require(quote.quoteStatus == QuoteStatus.CLOSE_PENDING, "PrivatePartyAFacet: Invalid state");
	// 	if (block.timestamp > quote.deadline) {
	// 		LibQuote.expireQuote(quoteId);
	// 		return QuoteStatus.OPENED;
	// 	} else {
	// 		quote.statusModifyTimestamp = block.timestamp;
	// 		quote.quoteStatus = QuoteStatus.CANCEL_CLOSE_PENDING;
	// 		return QuoteStatus.CANCEL_CLOSE_PENDING;
	// 	}
	// }
}
