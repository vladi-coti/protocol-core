import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

const CITED_BATCH_LOOPS = [
	"multiAccount/MultiAccount.sol",
	"facets/PartyA/PartyAFacet.sol",
	"libraries/LibSettlement.sol",
] as const

function makeSymbols(n: number) {
	return Array.from({ length: n }, (_, i) => ({
		symbolId: 0n,
		name: `M26SYM${i}`,
		isValid: true,
		minAcceptableQuoteValue: decimal(100n),
		minAcceptablePortionLF: decimal(1n, 16),
		tradingFee: decimal(1n, 16),
		maxLeverage: decimal(100n),
		fundingRateEpochDuration: 28800n,
		fundingRateWindowTime: 900n,
	}))
}

/**
 * M-26: batch loops must use uint256 counters so length > 255 does not panic.
 */
export function shouldBehaveLikeAuditM26(): void {
	describe("uint8 batch loop overflow", function () {
		it("M-26 static: cited batch loops use uint256 counters", function () {
			const contractsRoot = path.join(__dirname, "../../contracts")
			for (const rel of CITED_BATCH_LOOPS) {
				const src = fs.readFileSync(path.join(contractsRoot, rel), "utf8")
				expect(src, rel).to.match(/for\s*\(\s*uint256/)
				expect(src, rel).to.not.match(/for\s*\(\s*uint8/)
			}
		})

		it("M-26: addSymbols length 2 succeeds (control)", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			await runTx(context.controlFacet.connect(context.signers.admin).addSymbols(makeSymbols(2)))
		})

		it("M-26: addSymbols length 256 succeeds after uint256 counters", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			await runTx(context.controlFacet.connect(context.signers.admin).addSymbols(makeSymbols(256)))
		})
	})
}
