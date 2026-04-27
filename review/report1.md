1. in contracts/libraries/LibSolvency.sol:54-74

all four branches in isSolventAfterOpenPosition have the partyA/partyB adjustments swapped vs original symmio. for LONG with openedPrice >= marketPrice the original does:
partyAAvailableBalance -= int256(diff);
partyBAvailableBalance += int256(diff);

new code does the opposite: partyA += diff, partyB -= diff. same swap in all four branches (LONG/SHORT × above/below market).

This must be critical issue
2. contracts/libraries/muon/LibMuon.sol:27-37 and every LibMuon*.sol

verifyTSSAndGateway body is commented out, plus every timestamp expiry check across all muon libs. original symmio has them all enabled. the comment at line 24 literally says *"these lines should not be disabled in the production deployed version"*. anyone with a forged signature can fake any UPnL or price. can you explain the reasons behind this choice?
3. bodies commented out with // FIXME: pushes the contract size over the limit. selectors are still on the diamond, callers get a successful receipt, nothing happens: forceCancelQuote emergencyClosePosition settlePartyALiquidation resolveLiquidationDispute

happy path still works but some important paths needs those functions. i believe develop is not complete yet because we cant just remove those functionalities . am i right?
4. in contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol:32-42, the partyAAvailableBalanceForLiquidation lost its allocatedBalance parameter during the encryption refactor. the deferred liquidation flow used to call it twice:
once with the snapshot from the deferred sig (to verify partyA was insolvent), once with current balance.

both calls now read current storage and return the same value. so a partyA who was insolvent at snapshot time can deposit just enough to dodge liquidation before the tx lands. as a side effect, the second call and the "refund excess to partyA" branch (`if availableBalance > 0`) are now dead code.
also this is not a front running vector.

i tested it on chain and its conformed issue.