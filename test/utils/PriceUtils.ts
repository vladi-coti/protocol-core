import {ViewQuoteStructOutput} from "../../src/types/contracts/interfaces/ISymmio"
import {decimal} from "./Common"
import {randomBigNumber} from "./RandomUtils"

export async function getPrice(): Promise<bigint> {
	const def = 200000n * 10n ** 18n
	if (process.env.TEST_MODE !== "fuzz") return def
	return randomBigNumber(110000000000000000000n, 100000000000000000000n)
}

export function calculateExpectedClosePriceForForceClose(requestedClosePrice: bigint, penalty: bigint, isLongPosition: boolean): bigint {
	const a = (requestedClosePrice * penalty) / decimal(1n)
	return isLongPosition ? requestedClosePrice + a : requestedClosePrice - a
}

export function calculateExpectedAvgPriceForForceClose(avgClosedPrice: bigint, closedAmount: bigint, quantityToClose: bigint, expectedClosePrice: bigint): bigint {
	return ((avgClosedPrice * closedAmount) + (quantityToClose * expectedClosePrice)) / (closedAmount + quantityToClose)
}
