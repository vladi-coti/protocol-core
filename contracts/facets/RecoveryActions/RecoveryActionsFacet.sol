// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";
import "../../storages/QuoteStorage.sol";
import "../../storages/MuonStorage.sol";
import "../../libraries/LibAccount.sol";
import "../../libraries/LibQuote.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "../ForceActions/ForceActionsFacetEvents.sol";
import "../ForceActions/ForceActionsFacetImpl.sol";
import "../PartyBPositionActions/IPartyBPositionActionsEvents.sol";
import "../PartyBPositionActions/PartyBPositionActionsFacetImpl.sol";

contract RecoveryActionsFacet is Accessibility, Pausable, ForceActionsFacetEvents, IPartyBPositionActionsEvents {
	using MpcCore for gtUint256;

	function forceCancelQuote(uint256 quoteId) external notLiquidated(quoteId) whenNotPartyAActionsPaused {
		ForceActionsFacetImpl.forceCancelQuote(quoteId);
		emit ForceCancelQuote(quoteId, QuoteStatus.CANCELED);
	}

	function emergencyClosePosition(
		uint256 quoteId,
		PairUpnlAndPriceSig memory upnlSig
	) external whenNotPartyBActionsPaused onlyPartyBOfQuote(quoteId) notLiquidated(quoteId) {
		QuoteStorage.Layout storage quoteLayout = QuoteStorage.layout();
		Quote storage quote = quoteLayout.quotes[quoteId];

		gtUint256 gtFilledAmount = LibQuote.quoteOpenAmount(quote);
		address partyAAddr = LibAccount.getUserEncryptionAddress(quote.partyA);
		ctUint256 memory filledAmount = MpcCore.offBoardToUser(gtFilledAmount, partyAAddr);

		PartyBPositionActionsFacetImpl.emergencyClosePosition(quoteId, upnlSig);
		emit EmergencyClosePosition(
			quoteId,
			quote.partyA,
			quote.partyB,
			filledAmount,
			upnlSig.price,
			quote.quoteStatus,
			quoteLayout.closeIds[quoteId]
		);
	}
}
