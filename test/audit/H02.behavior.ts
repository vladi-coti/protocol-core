import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"

/**
 * H-02: signed encrypted accounting uses MpcCore.checkedAdd/Sub(gtInt256).
 */
export function shouldBehaveLikeAuditH02(): void {
	describe("LibAccount regression", function () {
		let context: RunContext
		let user: User

		beforeEach(async function () {
			context = await loadFixtureCompatible(initializeFixture)
			user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1500n), decimal(1200n))
		})

		it("H-02: sendQuote balance check still rejects unaffordable quotes", async function () {
			await expect(
				user.sendQuote(
					limitQuoteRequestBuilder()
						.partyBWhiteList([context.signers.hedger.address])
						.affiliate(context.multiAccount)
						.price(decimal(16n))
						.quantity(decimal(200n))
						.cva(decimal(2000n))
						.partyAmm(decimal(2000n))
						.lf(decimal(2000n))
						.build(),
				),
			).to.be.revertedWith("PartyAFacet: insufficient available balance")
		})
	})
}
