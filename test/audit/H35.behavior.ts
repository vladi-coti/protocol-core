import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType, QuoteStatus } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, decryptUint256, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyHighLowPriceSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible, timeCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-35: force-close PartyB liquidation credited liquidator share to msg.sender.
 * Force close is permissionless, so a third party could capture the LF tip.
 * Fix: force-close path pays quote.partyA; role-gated liquidatePartyB still pays msg.sender.
 */
export function shouldBehaveLikeAuditH35(): void {
	describe("force-close liquidation reward recipient", function () {
		it("H-35: third-party force close must credit liquidator share to PartyA", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const outsider = new User(context, context.signers.user2)
			await outsider.setup()

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
					.quantity(decimal(75n))
					.lf(decimal(50n))
					.build(),
			)
			await hedger.lockQuote(short)
			await hedger.openPosition(short, limitOpenRequestBuilder().filledAmount(decimal(75n)).build())

			await user.requestToClosePosition(
				short.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, short.quoteId))
					.closePrice(decimal(1n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			await runTx(context.controlFacet.setForceCloseMinSigPeriod(10))
			const quoteBefore = await context.viewFacet.getQuote(short.quoteId)
			await runTx(context.controlFacet.setForceCloseGapRatio(quoteBefore.symbolId, decimal(1n, 17)))
			await runTx(context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress))

			const partyA = await user.getAddress()
			const outsiderAddr = await outsider.getAddress()
			const partyABefore = (await user.getBalanceInfo()).allocatedBalances
			const outsiderBefore = (await outsider.getBalanceInfo()).allocatedBalances
			const hedgerBefore = await hedger.getBalanceInfo(partyA)
			const shortLf = await decryptUint256(context, quoteBefore.lockedValues.lf, user.getWallet())
			const liquidatorShare = BigInt(await context.viewFacet.liquidatorShare())
			const one = decimal(1n)

			const now = await getBlockTimestamp()
			const cooldowns = await context.viewFacet.forceCloseCooldowns()
			const startTime = cooldowns[0] + now
			const endTime = cooldowns[0] + now + 10n
			await timeCompatible.increase(cooldowns[0] + 10n + cooldowns[1] + 1n)

			await outsider.forceClosePosition(
				short.quoteId,
				await getDummyHighLowPriceSig(startTime, endTime, 0n, decimal(10n), decimal(35n, 17), decimal(35n, 17), 0n, 0n, 0n),
			)

			expect(await context.viewFacet.isPartyBLiquidated(await hedger.getAddress(), partyA)).to.equal(true)
			expect((await context.viewFacet.getQuote(short.quoteId)).quoteStatus).to.equal(QuoteStatus.CLOSE_PENDING)

			const partyAGain = (await user.getBalanceInfo()).allocatedBalances - partyABefore
			const outsiderGain = (await outsider.getBalanceInfo()).allocatedBalances - outsiderBefore
			expect(outsiderGain).to.equal(0n, "third-party caller must not receive liquidator share")
			expect(partyAGain).to.be.gt(0n, "PartyA must receive liquidation proceeds including tip")
			expect(outsiderAddr).to.not.equal(partyA)

			// Sanity: tip portion is non-zero in this fixture (remainingLf > 0).
			const retained = hedgerBefore.allocatedBalances - partyAGain
			expect(retained).to.be.gt(0n)
			const remainingLf = (retained * one) / (one - liquidatorShare)
			expect((remainingLf * liquidatorShare) / one).to.be.gt(0n)
			expect(shortLf).to.be.gt(0n)
		})
	})
}
