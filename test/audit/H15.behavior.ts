import "../utils/revertedWith"
import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { getDummySingleUpnlSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

export function shouldBehaveLikeAuditH15(): void {
	describe("PartyB liquidation LF exceed allocated", function () {
		it("H-15: PartyB +UPNL lifts available; insolvent PartyB with lf>alloc liquidates", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(20000n), decimal(10000n), decimal(8000n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(20000n), decimal(20000n))

			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			const entry = decimal(1n)
			const qty = decimal(50n)

			// PartyA SHORT @1 — PartyB profits when mark rises
			const lfQuote = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.cva(decimal(10n))
					.partyAmm(decimal(10n))
					.partyBmm(decimal(10n))
					.lf(decimal(200n))
					.quantity(qty)
					.price(entry)
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(2000n), partyA))
			await hedger.lockQuote(lfQuote, 0n, null)
			await hedger.openPosition(lfQuote, limitOpenRequestBuilder().filledAmount(qty).openPrice(entry).price(entry).build())

			const before = await hedger.getBalanceInfo(partyA)
			const positions = await context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
			const quoteIds = positions.map((q: any) => BigInt(q.id))
			const markProfit = decimal(100n)

			// Probe: pull beyond (alloc - locked) requires on-chain +UPNL at markProfit
			const locked = before.totalLockedPartyB
			const overLockedPull = before.allocatedBalances - locked + decimal(1n)
			await expect(
				context.accountFacet
					.connect(context.signers.hedger)
					.deallocateForPartyB(overLockedPull, partyA, await getDummySingleUpnlSig(0n, quoteIds, quoteIds.map(() => entry))),
			).to.be.revertedWith("AccountFacet: Will be liquidatable")

			await runTx(
				context.accountFacet
					.connect(context.signers.hedger)
					.deallocateForPartyB(overLockedPull, partyA, await getDummySingleUpnlSig(0n, quoteIds, quoteIds.map(() => markProfit))),
			)

			// Drain remaining available so lf > alloc (remainingLf must not revert on liquidate)
			let bal = await hedger.getBalanceInfo(partyA)
			const targetAlloc = bal.lockedLf - decimal(1n)
			const drain = bal.allocatedBalances - targetAlloc
			if (drain > 0n) {
				await runTx(
					context.accountFacet
						.connect(context.signers.hedger)
						.deallocateForPartyB(drain, partyA, await getDummySingleUpnlSig(0n, quoteIds, quoteIds.map(() => markProfit))),
				)
			}

			bal = await hedger.getBalanceInfo(partyA)
			expect(bal.lockedLf).to.be.gt(bal.allocatedBalances)

			// Drop mark so PartyB UPNL goes negative enough to insolvent (PartyA SHORT benefits from rise)
			const markForLiq = entry + (bal.lockedCva * decimal(1n)) / qty
			const partyBUpnl = ((markForLiq - entry) * qty) / decimal(1n)
			const available = bal.allocatedBalances - bal.lockedCva - bal.lockedLf + partyBUpnl
			expect(available).to.be.lt(0n, `must be insolvent; available=${available}`)

			await runTx(
				context.liquidationFacet
					.connect(context.signers.liquidator)
					.liquidatePartyB(partyB, partyA, await getDummySingleUpnlSig(0n, quoteIds, quoteIds.map(() => markForLiq))),
			)

			expect((await hedger.getBalanceInfo(partyA)).allocatedBalances).to.equal(0n)
			expect(await context.viewFacet.isPartyBLiquidated(partyB, partyA)).to.equal(true)
		})
	})
}
