import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType, QuoteStatus } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyHighLowPriceSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible, timeCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-34: force close only checks sig.endTime (+ second cooldown) <= quote.deadline,
 * not block.timestamp <= quote.deadline. Cancel-close expires when now > deadline.
 * Stale optionality: wait past deadline, submit a high-low window that ended before deadline.
 */
export function shouldBehaveLikeAuditH34(): void {
	describe("force close after close-request deadline", function () {
		it("H-34: force close must revert when block.timestamp is past quote.deadline", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(4000n), decimal(4000n))

			const long = await user.sendQuote()
			await hedger.lockQuote(long)
			await hedger.openPosition(long)

			const short = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await hedger.lockQuote(short)
			await hedger.openPosition(short)

			await runTx(context.controlFacet.setForceCloseMinSigPeriod(10))
			const quoteBefore = await context.viewFacet.getQuote(short.quoteId)
			await runTx(context.controlFacet.setForceCloseGapRatio(quoteBefore.symbolId, decimal(1n, 17)))
			await runTx(context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress))

			const cooldowns = await context.viewFacet.forceCloseCooldowns()
			const now = await getBlockTimestamp()
			// Deadline far enough for a valid sig window, but we will wait past it before force-close.
			const deadline = now + cooldowns[0] + 30n + cooldowns[1] + 50n
			await user.requestToClosePosition(
				short.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, short.quoteId))
					.closePrice(decimal(1n))
					.deadline(deadline)
					.build(),
			)

			const statusAt = (await context.viewFacet.getQuote(short.quoteId)).statusModifyTimestamp
			const startTime = statusAt + cooldowns[0]
			const endTime = startTime + 10n
			// Satisfy existing check: endTime + secondCooldown <= deadline
			expect(endTime + cooldowns[1]).to.be.lte(deadline)

			// Advance past deadline while keeping a pre-deadline price window.
			await timeCompatible.increase(deadline - (await getBlockTimestamp()) + 5n)
			expect(await getBlockTimestamp()).to.be.gt(deadline)

			await expect(
				user.forceClosePosition(
					short.quoteId,
					await getDummyHighLowPriceSig(startTime, endTime, 0n, decimal(10n), decimal(1n), decimal(1n), 0n, 0n, 0n),
				),
			).to.be.revertedWith("PartyBFacet: Close request is expired")

			expect((await context.viewFacet.getQuote(short.quoteId)).quoteStatus).to.equal(QuoteStatus.CLOSE_PENDING)
		})
	})
}
