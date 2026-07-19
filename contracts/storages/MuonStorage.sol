// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../libraries/LibLockedValues.sol";

struct SchnorrSign {
	uint256 signature;
	address owner;
	address nonce;
}

struct PublicKey {
	uint256 x;
	uint8 parity;
}

struct SingleUpnlSig {
	bytes reqId;
	uint256 timestamp;
	uint256[] quoteIds;
	uint256[] prices;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct SingleUpnlAndPriceSig {
	bytes reqId;
	uint256 timestamp;
	uint256 price;
	uint256[] quoteIds;
	uint256[] prices;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct PairUpnlSig {
	bytes reqId;
	uint256 timestamp;
	uint256[] partyAQuoteIds;
	uint256[] partyAPrices;
	uint256[] partyBQuoteIds;
	uint256[] partyBPrices;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct PairUpnlAndPriceSig {
	bytes reqId;
	uint256 timestamp;
	uint256 price;
	uint256[] partyAQuoteIds;
	uint256[] partyAPrices;
	uint256[] partyBQuoteIds;
	uint256[] partyBPrices;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct PairUpnlAndPricesSig {
	bytes reqId;
	uint256 timestamp;
	uint256[] symbolIds;
	uint256[] prices;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct DeferredLiquidationSig {
	bytes reqId; // Unique identifier for the liquidation request
	uint256 timestamp; // Timestamp when the liquidation signature was created
	uint256 liquidationBlockNumber; // Block number at which the user became insolvent
	uint256 liquidationTimestamp; // Timestamp when the user became insolvent
	/// @dev Public snapshot of PartyA allocated at insolvency. Kept after H-01 (UPNL is on-chain);
	/// classification / solvency for deferred must use this, not a post-sign top-up.
	uint256 liquidationAllocatedBalance;
	bytes liquidationId; // Unique identifier for the liquidation event
	uint256[] symbolIds; // List of symbol IDs involved in the liquidation
	uint256[] prices; // Corresponding prices of the symbols involved in the liquidation
	bytes gatewaySignature; // Signature from the gateway for verification
	SchnorrSign sigs; // Schnorr signature for additional verification
}

struct LiquidationSig {
	bytes reqId; // Unique identifier for the liquidation request
	uint256 timestamp; // Timestamp when the liquidation signature was created
	bytes liquidationId; // Unique identifier for the liquidation event
	uint256[] symbolIds; // List of symbol IDs involved in the liquidation
	uint256[] prices; // Corresponding prices of the symbols involved in the liquidation
	bytes gatewaySignature; // Signature from the gateway for verification
	SchnorrSign sigs; // Schnorr signature for additional verification
}

struct QuotePriceSig {
	bytes reqId;
	uint256 timestamp;
	uint256[] quoteIds;
	uint256[] prices;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct HighLowPriceSig {
	bytes reqId;
	uint256 timestamp;
	uint256 symbolId;
	uint256 highest;
	uint256 lowest;
	uint256 averagePrice;
	uint256 startTime;
	uint256 endTime;
	uint256 currentPrice;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

struct QuoteSettlementData {
	uint256 quoteId;
	uint256 currentPrice;
}

struct SettlementSig {
	bytes reqId;
	uint256 timestamp;
	QuoteSettlementData[] quotesSettlementsData;
	QuotePriceSig partyAPriceSig;
	QuotePriceSig[] partyBPriceSigs;
	bytes gatewaySignature;
	SchnorrSign sigs;
}

library MuonStorage {
	bytes32 internal constant MUON_STORAGE_SLOT = keccak256("diamond.standard.storage.muon");

	struct Layout {
		uint256 upnlValidTime; // UNUSED for freshness (H-01 path C); kept for storage layout / setMuonConfig ABI
		uint256 priceValidTime; // sole Muon signature freshness window
		uint256 priceQuantityValidTime; // UNUSED: Should be deleted later
		uint256 muonAppId;
		PublicKey muonPublicKey;
		address validGateway;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = MUON_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
