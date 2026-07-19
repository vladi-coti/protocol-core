import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { LiquidationType, PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { getDummyLiquidationSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-38: zero-CVA PartyA can select LATE, then liquidatePositions divides by totalCva=0.
 */
export function shouldBehaveLikeAuditH38(): void {
	describe("zero-CVA LATE divide-by-zero", function () {
		let context: RunContext
		let user: User
		let hedger: Hedger
		let liquidator: User

		beforeEach(async function () {
			context = await loadFixtureCompatible(initializeFixture)
			user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))

			hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))
		})

		it("H-38: accepts zero-CVA quote (control)", async function () {
			const quote = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.cva(decimal(0n))
					.partyAmm(decimal(97n))
					.lf(decimal(3n))
					.build(),
			)
			expect(quote.quoteId).to.not.equal(0n)
			const bal = await user.getBalanceInfo()
			expect(bal.pendingLockedCva).to.equal(0n)
		})

		it("H-38: LATE + zero total CVA liquidates without div-by-zero", async function () {
			const quote = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.cva(decimal(0n))
					.partyAmm(decimal(97n))
					.lf(decimal(3n))
					.build(),
			)
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const balanceInfo = await user.getBalanceInfo()
			expect(balanceInfo.lockedCva).to.equal(0n)
			const lf = balanceInfo.lockedLf
			expect(lf).to.be.gt(0n)

			// available = allocated - lf + upnl; LATE with cva=0 wants deficit == lf ⇒ upnl == -allocated.
			// SHORT @1 qty≈100: upnl = -(mark-1)*qty ⇒ mark = 1 + allocated/qty.
			const qty = decimal(100n)
			const price = decimal(1n) + (balanceInfo.allocatedBalances * decimal(1n)) / qty
			const upnl = -balanceInfo.allocatedBalances
			const sign = await getDummyLiquidationSig("0x10", upnl, [1n], [price], upnl, balanceInfo.allocatedBalances)

			await runTx(context.liquidationFacet.connect(context.signers.liquidator).liquidatePartyA(partyA, sign))
			await runTx(context.liquidationFacet.connect(context.signers.liquidator).setSymbolsPrice(partyA, sign))

			const liquidationState = await user.getLiquidatedStateOfPartyA()
			expect(liquidationState["liquidationType"]).to.equal(LiquidationType.LATE)

			await user.liquidatePendingPositions()
			// Pre-fix: LATE + totalCva=0 reverted (div by zero). Settle may dispute on UPNL mismatch; not in scope.
			await user.liquidatePositions([quote.quoteId])
			const open = await user.getOpenPositions()
			expect(open.length).to.equal(0)
		})
	})
}
