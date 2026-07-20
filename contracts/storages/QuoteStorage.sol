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

struct LockedValues {
	utUint256 cva;
	utUint256 lf;
	utUint256 partyAmm;
	utUint256 partyBmm;
}

struct UserLockedValues {
	ctUint256 cva;
	ctUint256 lf;
	ctUint256 partyAmm;
	ctUint256 partyBmm;
}

struct ObserverQuoteValues {
	ctUint256 openedPrice;
	ctUint256 initialOpenedPrice;
	ctUint256 requestedOpenPrice;
	ctUint256 marketPrice;
	ctUint256 quantity;
	ctUint256 closedAmount;
	ctUint256 avgClosedPrice;
	ctUint256 requestedClosePrice;
	ctUint256 quantityToClose;
	ctUint256 tradingFee;
	UserLockedValues initialLockedValues;
	UserLockedValues lockedValues;
}

struct GarbledLockedValues {
	gtUint256 cva;
	gtUint256 lf;
	gtUint256 partyAmm;
	gtUint256 partyBmm;
}

struct Quote {
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
	LockedValues initialLockedValues;
	LockedValues lockedValues;
	uint256 maxFundingRate;
	address partyA;
	address partyB;
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

/// @dev Public view return type — user/observer ciphertext only (no COTI system ciphertext).
struct ViewQuote {
	uint256 id;
	address[] partyBsWhiteList;
	uint256 symbolId;
	PositionType positionType;
	OrderType orderType;
	ctUint256 openedPrice;
	ctUint256 initialOpenedPrice;
	ctUint256 requestedOpenPrice;
	ctUint256 marketPrice;
	ctUint256 quantity;
	ctUint256 closedAmount;
	UserLockedValues initialLockedValues;
	UserLockedValues lockedValues;
	uint256 maxFundingRate;
	address partyA;
	address partyB;
	QuoteStatus quoteStatus;
	ctUint256 avgClosedPrice;
	ctUint256 requestedClosePrice;
	ctUint256 quantityToClose;
	uint256 parentId;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 lastFundingPaymentTimestamp;
	uint256 deadline;
	ctUint256 tradingFee;
	address affiliate;
}

// Struct to hold encrypted quote values to reduce stack depth
struct EncryptedQuoteValues {
	ctUint256 price;
	ctUint256 marketPrice;
	ctUint256 quantity;
	ctUint256 cva;
	ctUint256 lf;
	ctUint256 partyAmm;
	ctUint256 partyBmm;
	ctUint256 tradingFee;
}

// Struct to hold encrypted position values for OpenPosition events
struct EncryptedPositionValues {
	ctUint256 filledAmount;
	ctUint256 openedPrice;
}

struct PrivateQuoteParams {
	itUint256 encryptedPrice;
	itUint256 encryptedQuantity;
	itUint256 encryptedCva;
	itUint256 encryptedLf;
	itUint256 encryptedPartyAmm;
	itUint256 encryptedPartyBmm;
}

// Struct to hold encrypted open position parameters
struct PrivateOpenPositionParams {
	itUint256 encryptedFilledAmount;
	itUint256 encryptedOpenedPrice;
}

// Struct to hold encrypted close position parameters
struct PrivateClosePositionParams {
	itUint256 encryptedFilledAmount;
	itUint256 encryptedClosedPrice;
}

struct QuoteBasicParams {
	address[] partyBsWhiteList;
	uint256 symbolId;
	PositionType positionType;
	OrderType orderType;
	uint256 maxFundingRate;
	uint256 deadline;
	address affiliate;
}

library QuoteStorage {
	bytes32 internal constant QUOTE_STORAGE_SLOT = keccak256("diamond.standard.storage.quote");

	struct Layout {
		mapping(address => uint256[]) quoteIdsOf;
		mapping(uint256 => Quote) quotes;
		mapping(uint256 => ObserverQuoteValues) observerQuoteValues;
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
		bytes32 slot = QUOTE_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
