import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType, QuoteStatus } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, decryptUint256 } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-44: liquidatePendingPositionsPartyA zeros PartyB pending locked via direct offBoard,
 * skipping LibEncryption.storePartyBPendingLockedBalance — observer copy stays stale.
 */
export function shouldBehaveLikeAuditM44(): void {
	describe("liquidation cleanup observer sync", function () {
		it("M-44 static: pending PartyB zeroing uses storePartyBPendingLockedBalance", function () {
			const src = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			expect(src).to.include("LibEncryption.storePartyBPendingLockedBalance(accountLayout, quote.partyB, partyA, gtZeroLockedB)")
			expect(src).to.not.match(
				/partyBPendingLockedBalances\[quote\.partyB\]\[partyA\]\s*=\s*gtZeroLockedB\.offBoard/,
			)
		})

		it("M-44: after liquidatePending, PartyB pending locked is zero but observer pending stays nonzero", async function () {
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

			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()

			// SHORT@price=8 → insolvent; open via allocateForPartyB + affiliate (H-15-safe on sim)
			const open = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), partyA))
			await hedger.lockQuote(open, 0n, null)
			await hedger.openPosition(open)

			await runTx(
				context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.liquidator.address),
			)

			const pending = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.quantity(decimal(50n))
					.build(),
			)
			await hedger.lockQuote(pending, 0n, null)

			const [, , observerPendingBefore] = await context.viewFacet.observerBalanceInfoOfPartyB(partyB, partyA)
			const observerPendingCvaBefore = await decryptUint256(
				context,
				observerPendingBefore.cva,
				context.signers.liquidator,
			)
			expect(observerPendingCvaBefore, "observer pending must be set while quote is locked").to.be.greaterThan(0n)

			await user.liquidateAndSetSymbolPrices([1n], [decimal(8n)])
			await user.liquidatePendingPositions()

			expect((await context.viewFacet.getQuote(pending.quoteId)).quoteStatus).to.equal(QuoteStatus.LIQUIDATED_PENDING)

			const hedgerBalance = await hedger.getBalanceInfo(partyA)
			expect(hedgerBalance.pendingLockedCva).to.equal(0n)
			expect(hedgerBalance.totalPendingLockedPartyB).to.equal(0n)

			const [, , observerPendingAfter] = await context.viewFacet.observerBalanceInfoOfPartyB(partyB, partyA)
			const observerPendingCvaAfter = await decryptUint256(
				context,
				observerPendingAfter.cva,
				context.signers.liquidator,
			)
			expect(observerPendingCvaAfter, "M-44: observer pending must clear with primary").to.equal(0n)
		})
	})
}
