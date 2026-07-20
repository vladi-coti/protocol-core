import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { QuoteStatus } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"

/**
 * M-50: close-request creation must enforce the same proportional min as LibQuote.closeQuote.
 */
export function shouldBehaveLikeAuditM50(): void {
	describe("dust close request locks position", function () {
		it("M-50 static: requestToClosePosition calls requireMinProportionalCloseAmount", function () {
			const impl = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyA/PartyAFacetImpl.sol"),
				"utf8",
			)
			const fn = impl.slice(
				impl.indexOf("function requestToClosePosition"),
				impl.indexOf("function requestToCancelCloseRequest"),
			)
			expect(fn).to.include("requireMinProportionalCloseAmount")

			const lib = fs.readFileSync(path.join(__dirname, "../../contracts/libraries/LibQuote.sol"), "utf8")
			expect(lib).to.include("function requireMinProportionalCloseAmount")
			expect(lib).to.include("LibQuote: Low filled amount")
		})

		it("M-50: dust quantityToClose is rejected at request time", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const open = await user.sendQuote()
			await hedger.lockQuote(open)
			await hedger.openPosition(open)

			await expect(
				user.requestToClosePosition(
					open.quoteId,
					limitCloseRequestBuilder()
						.quantityToClose(1n)
						.closePrice(decimal(1n))
						.deadline((await getBlockTimestamp()) + 5000n)
						.build(),
				),
			).to.be.revertedWith("LibQuote: Low filled amount")

			expect((await context.viewFacet.getQuote(open.quoteId)).quoteStatus).to.equal(QuoteStatus.OPENED)
		})

		it("M-50: full close request still enters CLOSE_PENDING", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const open = await user.sendQuote()
			await hedger.lockQuote(open)
			await hedger.openPosition(open)

			await user.requestToClosePosition(
				open.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, open.quoteId))
					.closePrice(decimal(1n))
					.deadline((await getBlockTimestamp()) + 5000n)
					.build(),
			)

			expect((await context.viewFacet.getQuote(open.quoteId)).quoteStatus).to.equal(QuoteStatus.CLOSE_PENDING)
		})
	})
}
