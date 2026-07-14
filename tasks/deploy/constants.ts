export const FacetNames = [
	"AccountFacet",
	"AccountManagementFacet",
	"ControlFacet",
	"DiamondLoupeFacet",
	"LiquidationFacet",
	"LiquidationPositionsFacet",
	"LiquidationResolutionFacet",
	"PartyAFacet",
	"BridgeFacet",
	"ViewFacet",
	"FundingRateFacet",
	"ForceActionsFacet",
	"ForceCloseFacet",
	"SettleAndForceCloseFacet",
	"RecoveryActionsFacet",
	"SettlementFacet",
	"PartyBCloseActionsFacet",
	"PartyBPositionActionsFacet",
	"PartyBQuoteActionsFacet",
	"PartyBGroupActionsFacet",
]

export const LibraryNames = [
	"LibAccountEncryption",
	"ForceActionsFacetImpl",
	"PartyBGroupActionsFacetImpl",
]

export const DEPLOYMENT_LOG_FILE = "deployed.json"

export const testnetChainId = 7082400n
export const simCotiChainId = 7082401n
export const gasOptions = { gasLimit: 60000000, gasPrice: 1000000000 }