// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../../libraries/LibLockedValues.sol";
import "../../libraries/LibPrivateLockedValues.sol";
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
import "../../libraries/LibPrivateQuote.sol";

library PrivatePartyAFacetImpl {
	using MpcCore for gtUint256;
	using MpcCore for gtBool;
	using LockedValuesOps for LockedValues;
	using PrivateLockedValuesOps for EncryptedLockedValues;

	function sendPrivateQuote(
		address[] memory partyBsWhiteList,
		uint256 symbolId,
		PositionType positionType,
		OrderType orderType,
		itUint256 calldata encryptedPrice,
		itUint256 calldata encryptedQuantity,
		itUint256 calldata encryptedCva,
		itUint256 calldata encryptedLf,
		itUint256 calldata encryptedPartyAmm,
		itUint256 calldata encryptedPartyBmm,
		uint256 maxFundingRate,
		uint256 deadline,
		address affiliate,
		SingleUpnlAndPriceSig memory upnlSig
	) internal returns (uint256 currentId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		MAStorage.Layout storage maLayout = MAStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

		require(!LibAccessibility.hasRole(msg.sender, LibAccessibility.LIQUIDATOR_ROLE), "PrivatePartyAFacet: Liquidator can't be partyA");
		require(
			quoteLayout.partyAPendingQuotes[msg.sender].length < maLayout.pendingQuotesValidLength,
			"PrivatePartyAFacet: Number of pending quotes out of range"
		);
		require(symbolLayout.symbols[symbolId].isValid, "PrivatePartyAFacet: Symbol is not valid");
		require(deadline >= block.timestamp, "PrivatePartyAFacet: Low deadline");

		// Validate encrypted inputs without decrypting
		gtUint256 memory gtPrice = MpcCore.validateCiphertext(encryptedPrice);
		gtUint256 memory gtQuantity = MpcCore.validateCiphertext(encryptedQuantity);
		gtUint256 memory gtCva = MpcCore.validateCiphertext(encryptedCva);
		gtUint256 memory gtLf = MpcCore.validateCiphertext(encryptedLf);
		gtUint256 memory gtPartyAmm = MpcCore.validateCiphertext(encryptedPartyAmm);
		gtUint256 memory gtPartyBmm = MpcCore.validateCiphertext(encryptedPartyBmm);

		revert("test1");

		// Create encrypted locked values struct
		EncryptedLockedValues memory encryptedLockedValues = EncryptedLockedValues({
			cva: gtCva,
			lf: gtLf,
			partyAmm: gtPartyAmm,
			partyBmm: gtPartyBmm
		});

		// Calculate encrypted trading price based on order type
		gtUint256 memory gtTradingPrice = MpcCore.mux(
			MpcCore.eq(MpcCore.setPublic256(uint256(orderType)), MpcCore.setPublic256(uint256(OrderType.LIMIT))),
			gtPrice,
			MpcCore.setPublic256(upnlSig.price)
		);

		// Perform encrypted validations
		gtUint256 memory encryptedTotalForPartyA = PrivateLockedValuesOps.totalForPartyA(encryptedLockedValues);

		// Check minimum LF requirement: lf >= (minAcceptablePortionLF * totalForPartyA) / 1e18
		gtUint256 memory minLfRequired = encryptedTotalForPartyA.mul(MpcCore.setPublic256(symbolLayout.symbols[symbolId].minAcceptablePortionLF)).div(
			MpcCore.setPublic256(1e18)
		);
		gtBool lfSufficient = gtLf.ge(minLfRequired);

		// Check minimum quote value: totalForPartyA >= minAcceptableQuoteValue
		gtBool quoteSufficient = encryptedTotalForPartyA.ge(MpcCore.setPublic256(symbolLayout.symbols[symbolId].minAcceptableQuoteValue));

		// Calculate encrypted trading fee: (quantity * tradingPrice * tradingFee) / 1e36
		gtUint256 memory encryptedTradingFee = gtQuantity
			.mul(gtTradingPrice)
			.mul(MpcCore.setPublic256(symbolLayout.symbols[symbolId].tradingFee))
			.div(MpcCore.setPublic256(1e36));

		// Calculate total required balance: totalForPartyA + tradingFee
		gtUint256 memory totalRequired = encryptedTotalForPartyA.add(encryptedTradingFee);

		// Check available balance sufficiency
		gtUint256 memory encryptedAvailableBalance = MpcCore.setPublic256(uint256(LibAccount.partyAAvailableForQuote(upnlSig.upnl, msg.sender)));
		gtBool balanceSufficient = encryptedAvailableBalance.ge(totalRequired);

		// Combine all validation results
		gtBool allValidationsPassed = lfSufficient.and(quoteSufficient).and(balanceSufficient);

		// Only decrypt the final validation result for require check
		require(MpcCore.decrypt(allValidationsPassed), "PrivatePartyAFacet: Validation failed");

		// Additional non-encrypted validations
		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			require(partyBsWhiteList[i] != msg.sender, "PrivatePartyAFacet: Sender isn't allowed in partyBWhiteList");
		}
		require(maLayout.affiliateStatus[affiliate] || affiliate == address(0), "PrivatePartyAFacet: Invalid affiliate");

		LibMuonPartyA.verifyPartyAUpnlAndPrice(upnlSig, msg.sender, symbolId);

		// Store encrypted locked values directly
		PrivateLockedValuesOps.addToPendingLocked(msg.sender, encryptedLockedValues);

		currentId = ++quoteLayout.lastId;

		// Create quote with placeholder values (actual encrypted values stored separately)
		Quote memory quote = Quote({
			id: currentId,
			partyBsWhiteList: partyBsWhiteList,
			symbolId: symbolId,
			positionType: positionType,
			orderType: orderType,
			openedPrice: 0,
			initialOpenedPrice: 0,
			requestedOpenPrice: 1, // Placeholder for private quotes
			marketPrice: upnlSig.price,
			quantity: 1, // Placeholder for private quotes
			closedAmount: 0,
			lockedValues: LockedValues(1, 1, 1, 1), // Placeholder values
			initialLockedValues: LockedValues(1, 1, 1, 1), // Placeholder values
			maxFundingRate: maxFundingRate,
			partyA: msg.sender,
			partyB: address(0),
			quoteStatus: QuoteStatus.PENDING,
			avgClosedPrice: 0,
			requestedClosePrice: 0,
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			quantityToClose: 0,
			lastFundingPaymentTimestamp: 0,
			deadline: deadline,
			tradingFee: symbolLayout.symbols[symbolId].tradingFee,
			affiliate: affiliate
		});

		// Store quote and update indexes
		quoteLayout.quoteIdsOf[msg.sender].push(currentId);
		quoteLayout.partyAPendingQuotes[msg.sender].push(currentId);
		quoteLayout.quotes[currentId] = quote;

		// Store encrypted parameters in private storage
		address partyB = partyBsWhiteList.length == 1 ? partyBsWhiteList[0] : address(0);
		LibPrivateQuote.createPrivateQuote(
			currentId,
			encryptedQuantity,
			encryptedPrice,
			encryptedCva,
			encryptedLf,
			encryptedPartyAmm,
			encryptedPartyBmm,
			msg.sender,
			partyB
		);

		// Only decrypt trading fee when we need to deduct it from allocated balances
		uint256 fee = MpcCore.decrypt(encryptedTradingFee);
		accountLayout.allocatedBalances[msg.sender] -= fee;
		emit SharedEvents.BalanceChangePartyA(msg.sender, fee, SharedEvents.BalanceChangeType.PLATFORM_FEE_OUT);
	}

	function requestToCancelQuote(uint256 quoteId) internal returns (QuoteStatus result) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Quote storage quote = QuoteStorage.layout().quotes[quoteId];

		require(quote.quoteStatus == QuoteStatus.PENDING || quote.quoteStatus == QuoteStatus.LOCKED, "PrivatePartyAFacet: Invalid state");

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

		require(quote.quoteStatus == QuoteStatus.OPENED, "PrivatePartyAFacet: Invalid state");
		require(deadline >= block.timestamp, "PrivatePartyAFacet: Low deadline");
		require(LibQuote.quoteOpenAmount(quote) >= quantityToClose, "PrivatePartyAFacet: Invalid quantityToClose");

		// check that remaining position is not too small
		if (LibQuote.quoteOpenAmount(quote) > quantityToClose) {
			require(
				((LibQuote.quoteOpenAmount(quote) - quantityToClose) * quote.lockedValues.totalForPartyA()) / LibQuote.quoteOpenAmount(quote) >=
					symbolLayout.symbols[quote.symbolId].minAcceptableQuoteValue,
				"PrivatePartyAFacet: Remaining quote value is low"
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

		require(quote.quoteStatus == QuoteStatus.CLOSE_PENDING, "PrivatePartyAFacet: Invalid state");
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
