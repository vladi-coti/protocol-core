import { Contract, ContractFactory } from "ethers"

import { getSelectors } from "./diamondCut"

type SelectorOverride = {
	include?: string[]
	exclude?: string[]
}

export const FACET_SELECTOR_OVERRIDES: Record<string, SelectorOverride> = {
	ForceActionsFacet: {
		exclude: ["forceCancelQuote"],
	},
	PartyBPositionActionsFacet: {
		exclude: ["emergencyClosePosition"],
	},
	LiquidationFacet: {
		exclude: ["settlePartyALiquidation", "resolveLiquidationDispute"],
	},
	RecoveryActionsFacet: {
		include: ["forceCancelQuote", "emergencyClosePosition"],
	},
	LiquidationResolutionFacet: {
		include: ["settlePartyALiquidation", "resolveLiquidationDispute"],
	},
}

export function getFacetSelectors(
	ethers: any,
	facetName: string,
	contract: Contract | ContractFactory
): string[] {
	const selectorHelper = getSelectors(ethers, contract)
	const override = FACET_SELECTOR_OVERRIDES[facetName]

	if (!override) {
		return selectorHelper.selectors
	}

	if (override.include) {
		return selectorHelper.get(override.include)
	}

	if (override.exclude) {
		return selectorHelper.remove(override.exclude)
	}

	return selectorHelper.selectors
}
