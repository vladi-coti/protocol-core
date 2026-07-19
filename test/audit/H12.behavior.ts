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
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyHighLowPriceSig, getDummyPriceSig, getDummySettlementSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible, timeCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"
import { QuoteSettlementDataStructOutput } from "../../src/types/contracts/facets/Settlement/ISettlementFacet"

/**
 * H-12: settleAndForceClosePosition must settle against quote.partyA (not msg.sender).
 * Third-party force-close + settlement should close the quote.
 */
export function shouldBehaveLikeAuditH12(): void {
	describe("settleAndForceClose wrong PartyA", function () {
		let context: RunContext
		let user: User
		let hedger: Hedger
		let quoteLongId: bigint
		let quoteShortId: bigint
		let symbolId: bigint

		beforeEach(async function () {
			context = await loadFixtureCompatible(initializeFixture)

			user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			// Pre-H01 injected +150 PartyB UPNL for settlement solvency; with on-chain UPNL≈0
			// the hedger needs enough allocated to clear alloc - cva - lf after both opens.
			await hedger.setBalances(decimal(5000n), decimal(5000n))
			await runTx(
				context.accountFacet
					.connect(context.signers.hedger)
					.allocateForPartyB(decimal(2000n), await user.getAddress()),
			)

			const long = await user.sendQuote()
			quoteLongId = long.quoteId
			await hedger.lockQuote(long)
			await hedger.openPosition(long)

			const short = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.quantity(decimal(75n))
					.build(),
			)
			quoteShortId = short.quoteId
			await hedger.lockQuote(short)
			await hedger.openPosition(short, limitOpenRequestBuilder().filledAmount(decimal(75n)).build())

			await user.requestToClosePosition(
				quoteLongId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, quoteLongId))
					.closePrice(decimal(5n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)
			await user.requestToClosePosition(
				quoteShortId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, quoteShortId))
					.closePrice(decimal(5n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			await runTx(context.controlFacet.setForceCloseMinSigPeriod(10))
			symbolId = (await context.viewFacet.getQuote(quoteLongId)).symbolId
			await runTx(context.controlFacet.setForceCloseGapRatio(symbolId, decimal(1n, 17)))
			await runTx(context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress))
		})

		async function prepareSigTimes(period: bigint = 100n) {
			const now = await getBlockTimestamp()
			const cooldowns = await context.viewFacet.forceCloseCooldowns()
			const firstCooldown = cooldowns[0]
			const secondCooldown = cooldowns[1]
			const startTime = firstCooldown + now
			const endTime = firstCooldown + now + period
			await timeCompatible.increase(firstCooldown + period + secondCooldown + 1n)
			return [startTime, endTime] as const
		}

		async function bookPriceSigs(mark: bigint) {
			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			const partyAPositions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
			const partyBPositions = await context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
			return {
				partyAPriceSig: await getDummyPriceSig(
					partyAPositions.map((q: any) => BigInt(q.id)),
					partyAPositions.map(() => mark),
				),
				partyBPriceSig: await getDummyPriceSig(
					partyBPositions.map((q: any) => BigInt(q.id)),
					partyBPositions.map(() => mark),
				),
			}
		}

		it("H-12: PartyA settleAndForceClose succeeds (control)", async function () {
			const [startTime, endTime] = await prepareSigTimes()
			const mark = decimal(1n) // entry — UPNL≈0 like pre-H01 dummy signed upnl
			const highLowSig = await getDummyHighLowPriceSig(
				startTime,
				endTime,
				0n,
				decimal(8n),
				decimal(6n),
				decimal(5n),
				symbolId,
				decimal(150n),
				0n,
			)
			const settlementSig = await getDummySettlementSig(0n, [150n], [
				{
					quoteId: quoteShortId,
					currentPrice: decimal(7n),
					partyBUpnlIndex: 0n,
				} as QuoteSettlementDataStructOutput,
			])
			const { partyAPriceSig, partyBPriceSig } = await bookPriceSigs(mark)
			;(settlementSig as any).partyAPriceSig = partyAPriceSig
			;(settlementSig as any).partyBPriceSigs = [partyBPriceSig]

			await runTx(
				context.forceCloseFacet
					.connect(context.signers.user)
					.settleAndForceClosePosition(quoteLongId, highLowSig, settlementSig, [decimal(5n)], partyAPriceSig, partyBPriceSig),
			)
			expect((await context.viewFacet.getQuote(quoteLongId)).quoteStatus).to.equal(QuoteStatus.CLOSED)
		})

		it("H-12: third-party caller settles against quote.partyA", async function () {
			const [startTime, endTime] = await prepareSigTimes()
			const mark = decimal(1n)
			const highLowSig = await getDummyHighLowPriceSig(
				startTime,
				endTime,
				0n,
				decimal(8n),
				decimal(6n),
				decimal(5n),
				symbolId,
				decimal(150n),
				0n,
			)
			const settlementSig = await getDummySettlementSig(0n, [150n], [
				{
					quoteId: quoteShortId,
					currentPrice: decimal(7n),
					partyBUpnlIndex: 0n,
				} as QuoteSettlementDataStructOutput,
			])
			const { partyAPriceSig, partyBPriceSig } = await bookPriceSigs(mark)
			;(settlementSig as any).partyAPriceSig = partyAPriceSig
			;(settlementSig as any).partyBPriceSigs = [partyBPriceSig]

			await runTx(
				context.forceCloseFacet
					.connect(context.signers.user2)
					.settleAndForceClosePosition(quoteLongId, highLowSig, settlementSig, [decimal(5n)], partyAPriceSig, partyBPriceSig),
			)

			expect((await context.viewFacet.getQuote(quoteLongId)).quoteStatus).to.equal(QuoteStatus.CLOSED)
		})
	})
}
