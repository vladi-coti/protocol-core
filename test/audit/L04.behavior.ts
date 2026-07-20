import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { loadFixtureCompatible } from "../utils/testHelpers"

/**
 * L-04: start past end underflows in pagination clamps → panic 0x11.
 * Design choice / wontfix: invalid range should fail loud, not soft-empty.
 */
export function shouldBehaveLikeAuditL04(): void {
	describe("pagination start past end", function () {
		it("L-04 static: ViewFacet keeps length-start clamp (no soft empty page helper)", function () {
			const view = fs.readFileSync(path.join(__dirname, "../../contracts/facets/ViewFacet/ViewFacet.sol"), "utf8")
			expect(view).to.not.match(/function _pageSize\b/)
			const getSymbols = view.slice(view.indexOf("function getSymbols"), view.indexOf("function symbolsByQuoteId"))
			expect(getSymbols).to.match(/lastId - start/)
			expect(view).to.match(/quoteIdsOf\[partyA\]\.length - start/)
		})

		it("L-04: getQuotes(start past length) reverts (intentional bounds)", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const partyA = await context.signers.user.getAddress()
			const len = await context.viewFacet.quotesLength(partyA)
			await expect(context.viewFacet.getQuotes(partyA, len + 1n, 10n)).to.be.reverted
		})

		it("L-04: getSymbols(start past lastId) reverts (intentional bounds)", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const known = await context.viewFacet.getSymbols(0n, 100n)
			await expect(context.viewFacet.getSymbols(BigInt(known.length) + 1n, 10n)).to.be.reverted
		})
	})
}
