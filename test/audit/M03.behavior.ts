import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-03: dispute accumulator caps positive PartyB settlement at partyBAllocated only.
 * settlePartyALiquidation adds settlement CVA before applying PnL (payable = alloc+cva).
 * Omitting CVA from the cap marks disputed even when settle would pay the full expected amount.
 */
export function shouldBehaveLikeAuditM03(): void {
	describe("dispute accumulator ignores settlement CVA", function () {
		it("M-03 static: positive-leg cap includes settlement CVA (matches settle)", function () {
			const src = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			const update = src.slice(
				src.indexOf("function _updateLiquidationAccumulator"),
				src.indexOf("function _isLiquidationAccumulatorDisputed"),
			)
			expect(update).to.include("partyBAllocatedBalances[partyB][partyA]")
			expect(update).to.include("settlementStates[partyA][partyB].cva")
			expect(update).to.include("gtPayable")
		})

		it("M-03: winning PartyB with allocated < expected <= allocated+cva does not false-dispute", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(400n), decimal(180n), decimal(180n))

			const liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))

			const hedgerLoss = new Hedger(context, context.signers.hedger)
			await hedgerLoss.setup()
			await hedgerLoss.setBalances(decimal(10000n), decimal(10000n))

			const hedgerWin = new Hedger(context, context.signers.hedger2)
			await hedgerWin.setup()
			await hedgerWin.setBalances(decimal(5000n), decimal(5000n))

			const partyA = await user.getAddress()

			const long = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.LONG)
					.quantity(decimal(260n))
					.price(decimal(1n))
					.cva(decimal(22n))
					.partyAmm(decimal(50n))
					.partyBmm(decimal(40n))
					.lf(decimal(3n))
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(2000n), partyA))
			await hedgerLoss.lockQuote(long, 0n, null)
			await hedgerLoss.openPosition(long, limitOpenRequestBuilder().filledAmount(decimal(260n)).build())

			const shortCva = decimal(30n)
			const winAlloc = decimal(45n)
			const short = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger2.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.quantity(decimal(100n))
					.price(decimal(1n))
					.cva(shortCva)
					.partyAmm(decimal(10n))
					.partyBmm(decimal(5n))
					.lf(decimal(3n))
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger2).allocateForPartyB(winAlloc, partyA))
			await hedgerWin.lockQuote(short, 0n, null)
			await hedgerWin.openPosition(short)

			// mark 0.25: long loss 195, short profit 75; 45 < 75 <= 75 — previously false-disputed.
			const mark = decimal(25n, 16)
			await user.liquidateAndSetSymbolPrices([1n], [mark])
			await user.liquidatePendingPositions()
			await user.liquidatePositions([long.quoteId, short.quoteId])

			const state = await user.getLiquidatedStateOfPartyA()
			expect(state.disputed).to.equal(false)

			const winAddr = await hedgerWin.getAddress()
			const [settlement] = await context.viewFacet.getSettlementStates(partyA, [winAddr])
			const expected = await (context.signers.user as any).decryptInt256(settlement.expectedAmount)
			const cva = await (context.signers.user as any).decryptUint256(settlement.cva)
			const winBal = await hedgerWin.getBalanceInfo(partyA)
			expect(expected).to.be.gt(0n)
			expect(expected).to.be.gt(winBal.allocatedBalances)
			expect(expected).to.be.lte(winBal.allocatedBalances + cva)
		})
	})
}
