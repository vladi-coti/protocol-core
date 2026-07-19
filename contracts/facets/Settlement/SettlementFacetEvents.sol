// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/MuonStorage.sol";
import { ctUint256 } from "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

interface SettlementFacetEvents {
	// H-11: do not emit updatedPrices — those become encrypted openedPrice; pubkey event would leak them.
	// (Calldata of settleUpnl still carries plaintext args; event must not rebroadcast.)
	event SettleUpnl(
		QuoteSettlementData[] settlementData,
		address partyA,
		ctUint256 newPartyAAllocatedBalance,
		ctUint256[] newPartyBsAllocatedBalances
	);
}
