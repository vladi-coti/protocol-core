import {expect} from "chai"
import {BigNumber as BN} from "bignumber.js"

export function safeDiv(a: bigint, b: bigint): bigint {
	const value = new BN(a.toString()).dividedBy(new BN(b.toString()))
	if (value.isLessThan(1) && value.isGreaterThan(0)) {
		throw new Error("Division led to fraction!")
	}
	return BigInt(value.toFixed(0))
}

BN.set({ROUNDING_MODE: BN.ROUND_CEIL})

export function roundToPrecision(a: bigint, precision: number): bigint {
	const decimalValue = new BN(a.toString()).dividedBy(new BN(10).pow(18))
	const rounded = decimalValue.toFixed(precision)
	// Parse the decimal string, multiply by 10^18, then convert to BigInt
	const roundedBN = new BN(rounded).multipliedBy(new BN(10).pow(18))
	return BigInt(roundedBN.toFixed(0))
}

export function expectToBeApproximately(a: bigint, b: bigint): void {
	expect(b - a).to.be.lte(10n)
}
