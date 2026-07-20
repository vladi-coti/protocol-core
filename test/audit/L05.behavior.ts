import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"

/**
 * L-05: getNextQuoteId / getNextBridgeTransactionId return lastId (last assigned),
 * not lastId+1. Name is misleading; semantics match NextQuoteIDVerifier and
 * BridgeFacet tests (id + 1n). Design-choice / wontfix — no ABI/behavior change.
 */
export function shouldBehaveLikeAuditL05(): void {
	describe("next-ID helpers return last assigned", function () {
		it("L-05 static: helpers return storage lastId; NatSpec says last assigned", function () {
			const view = fs.readFileSync(path.join(__dirname, "../../contracts/facets/ViewFacet/ViewFacet.sol"), "utf8")
			expect(view).to.match(/function getNextQuoteId\([^)]*\)[^{]*\{[^}]*return QuoteStorage\.layout\(\)\.lastId/)
			expect(view).to.match(/function getNextBridgeTransactionId\([^)]*\)[^{]*\{[^}]*return BridgeStorage\.layout\(\)\.lastId/)
			expect((view.match(/last assigned/gi) || []).length).to.be.greaterThanOrEqual(2)

			const verifier = fs.readFileSync(
				path.join(__dirname, "../../contracts/helpers/NextQuoteIDVerifier.sol"),
				"utf8",
			)
			expect(verifier).to.match(/quoteId == lastQuoteId/)
			expect(verifier).to.match(/last assigned/i)
		})

		it("L-05: getNextQuoteId equals last created quote; next create is +1", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const before = await context.viewFacet.getNextQuoteId()
			const { quoteId } = await user.sendQuote()
			const after = await context.viewFacet.getNextQuoteId()

			expect(quoteId).to.equal(before + 1n)
			expect(after).to.equal(quoteId)
			expect(after).to.equal(before + 1n)
		})
	})
}
