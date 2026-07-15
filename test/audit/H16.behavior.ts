import "../utils/revertedWith"
import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { LiquidationType, PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitFillCloseRequestBuilder } from "../models/requestModels/FillCloseRequest"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyLiquidationSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

function classifyLiquidationType(allocated: bigint, cva: bigint, lf: bigint, upnl: bigint): LiquidationType {
	const available = allocated - cva - lf + upnl
	expect(available < 0n, `must be insolvent; available=${available}`).to.equal(true)
	const deficit = -available
	if (deficit < lf) return LiquidationType.NORMAL
	if (deficit <= lf + cva) return LiquidationType.LATE
	return LiquidationType.OVERDUE
}

/**
 * H-16: deferred liquidation proves insolvency from signed allocated snapshot,
 * then classifies NORMAL/LATE/OVERDUE from *current* allocated — drift after sign.
 */
export function shouldBehaveLikeAuditH16(): void {
	describe("deferred liquidation snapshot drift", function () {
		it("H-16: liquidation type must follow signed allocated snapshot, not post-sign top-up", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			// Sim warm-up then flatten so SHORT@8 is insolvent alone.
			const warm = await user.sendQuote()
			await hedger.lockQuote(warm)
			await hedger.openPosition(warm)
			const warmQty = await getQuoteQuantity(context, warm.quoteId)
			await user.requestToClosePosition(
				warm.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(warmQty)
					.closePrice(decimal(1n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)
			await hedger.fillCloseRequest(
				warm.quoteId,
				limitFillCloseRequestBuilder().filledAmount(warmQty).closedPrice(decimal(1n)).build(),
			)

			const quote = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.quantity(decimal(75n))
					.build(),
			)
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote, limitOpenRequestBuilder().filledAmount(decimal(75n)).build())

			const partyA = await user.getAddress()
			const price = decimal(8n)
			const snapshot = await user.getBalanceInfo()
			const upnl = await user.getUpnl(async () => price)
			const totalUnrealizedLoss = await user.getTotalUnrealisedLoss(async () => price)

			const snapshotType = classifyLiquidationType(
				snapshot.allocatedBalances,
				snapshot.lockedCva,
				snapshot.lockedLf,
				upnl,
			)
			expect(snapshotType).to.not.equal(LiquidationType.NONE)

			// Post-sign deposit: shrink deficit enough to flip type but stay insolvent.
			const snapDeficit = -(snapshot.allocatedBalances - snapshot.lockedCva - snapshot.lockedLf + upnl)
			expect(snapDeficit >= snapshot.lockedLf, `need non-NORMAL snapshot; deficit=${snapDeficit} lf=${snapshot.lockedLf}`).to.equal(
				true,
			)
			const targetDeficit = snapshot.lockedLf - 1n
			const topUp = snapDeficit - targetDeficit
			expect(topUp > 0n).to.equal(true)
			await runTx(context.accountFacet.connect(context.signers.user).allocate(topUp))

			const after = await user.getBalanceInfo()
			const currentType = classifyLiquidationType(
				after.allocatedBalances,
				after.lockedCva,
				after.lockedLf,
				upnl,
			)
			expect(currentType).to.equal(LiquidationType.NORMAL)
			expect(currentType !== snapshotType, `fixture must drift; snap=${snapshotType} cur=${currentType}`).to.equal(true)

			const deferredSig = await getDummyLiquidationSig(
				"0x16",
				upnl,
				[1n],
				[price],
				totalUnrealizedLoss,
				snapshot.allocatedBalances,
			)

			await runTx(context.liquidationFacet.connect(context.signers.liquidator).deferredLiquidatePartyA(partyA, deferredSig))
			await runTx(context.liquidationFacet.connect(context.signers.liquidator).deferredSetSymbolsPrice(partyA, deferredSig))

			const state = await user.getLiquidatedStateOfPartyA()
			expect(state.liquidationType, `type must match snapshot=${snapshotType} not current=${currentType}`).to.equal(
				snapshotType,
			)
		})
	})
}
