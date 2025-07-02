// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

enum PositionType {
	LONG,
	SHORT
}

enum OrderType {
	LIMIT,
	MARKET
}

enum QuoteStatus {
	PENDING, //0
	LOCKED, //1
	CANCEL_PENDING, //2
	CANCELED, //3
	OPENED, //4
	CLOSE_PENDING, //5
	CANCEL_CLOSE_PENDING, //6
	CLOSED, //7
	LIQUIDATED, //8
	EXPIRED, //9
	LIQUIDATED_PENDING //10
}

struct PrivateLockedValues {
	utUint256 cva;
	utUint256 lf;
	utUint256 partyAmm;
	utUint256 partyBmm;
}

struct GarbledPrivateLockedValues {
	gtUint256 cva;
	gtUint256 lf;
	gtUint256 partyAmm;
	gtUint256 partyBmm;
}

struct PrivateQuote {
	uint256 id;
	address[] partyBsWhiteList;
	uint256 symbolId;
	PositionType positionType;
	OrderType orderType;
	// Price of quote which PartyB opened in 18 decimals (encrypted)
	utUint256 openedPrice;
	utUint256 initialOpenedPrice;
	// Price of quote which PartyA requested in 18 decimals (encrypted)
	utUint256 requestedOpenPrice;
	utUint256 marketPrice;
	// Quantity of quote which PartyA requested in 18 decimals (encrypted)
	utUint256 quantity;
	// Quantity of quote which PartyB has closed until now in 18 decimals (encrypted)
	utUint256 closedAmount;
	PrivateLockedValues initialLockedValues;
	PrivateLockedValues lockedValues;
	uint256 maxFundingRate;
	// Encrypted addresses converted to uint256 for privacy
	utUint256 partyA;
	utUint256 partyB;
	QuoteStatus quoteStatus;
	utUint256 avgClosedPrice;
	utUint256 requestedClosePrice;
	utUint256 quantityToClose;
	// handle partially open position
	uint256 parentId;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 lastFundingPaymentTimestamp;
	uint256 deadline;
	utUint256 tradingFee;
	address affiliate;
}

library PrivateQuoteStorage {
	bytes32 internal constant PRIVATE_QUOTE_STORAGE_SLOT = keccak256("diamond.standard.storage.privatequote");

	struct Layout {
		mapping(address => uint256[]) quoteIdsOf;
		mapping(uint256 => PrivateQuote) quotes;
		mapping(address => uint256) partyAPositionsCount;
		mapping(address => mapping(address => uint256)) partyBPositionsCount;
		mapping(address => uint256[]) partyAPendingQuotes;
		mapping(address => mapping(address => uint256[])) partyBPendingQuotes;
		mapping(address => uint256[]) partyAOpenPositions;
		mapping(uint256 => uint256) partyAPositionsIndex;
		mapping(address => mapping(address => uint256[])) partyBOpenPositions;
		mapping(uint256 => uint256) partyBPositionsIndex;
		uint256 lastId;
		uint256 lastCloseId;
		mapping(uint256 => uint256) closeIds;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = PRIVATE_QUOTE_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
