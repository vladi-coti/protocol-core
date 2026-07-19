import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp } from "../utils/Common"
import { getDummyLiquidationSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-02: symbolsPrices keyed by (partyA, symbol) with timestamp only; cleanup does not clear them.
 * A later liquidation with the same Muon timestamp can skip setSymbolsPrice and still pass
 * "Price should be set", settling with the stale stored price.
 */
export function shouldBehaveLikeAuditM02(): void {
	describe("stale liquidation symbol price reuse", function () {
		it("M-02 static: positions require timestamp and liquidationId-bound price", function () {
			const src = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			expect(src).to.include("symbolPriceLiquidationId[partyA][quote.symbolId]")
			expect(src).to.include("symbolPriceLiquidationId[partyA][symbolId] = keccak256(liquidationSig.liquidationId)")
			const settleCleanup = src.slice(src.lastIndexOf("function settlePartyALiquidation"), src.indexOf("function liquidatePartyB"))
			expect(settleCleanup).to.include("liquidationStatus[partyA] = false")
		})

		it("M-02: second liquidation with same timestamp can liquidate positions without setSymbolsPrice", async function () {
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
			const open1 = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), partyA))
			await hedger.lockQuote(open1, 0n, null)
			await hedger.openPosition(open1)

			const price1 = decimal(8n)
			// Fixture leaves upnlValidTime=0 → expiry is block.timestamp <= sig.timestamp.
			// Default dummy sigs are only +60s; pin far ahead so reuse still works on slow testnet.
			const reusedTimestamp = await getBlockTimestamp(3600n)
			const firstUpnl = await user.getUpnl(async () => price1)
			const firstLoss = await user.getTotalUnrealisedLoss(async () => price1)
			const firstAlloc = (await user.getBalanceInfo()).allocatedBalances
			const firstSig = await getDummyLiquidationSig("0x10", firstUpnl, [1n], [price1], firstLoss, firstAlloc)
			firstSig.timestamp = reusedTimestamp
			firstSig.liquidationTimestamp = reusedTimestamp
			await runTx(context.liquidationFacet.connect(context.signers.liquidator).liquidatePartyA(partyA, firstSig))
			await runTx(context.liquidationFacet.connect(context.signers.liquidator).setSymbolsPrice(partyA, firstSig))

			await user.liquidatePendingPositions()
			await user.liquidatePositions([open1.quoteId])
			await user.settleLiquidation()
			expect(await context.viewFacet.isPartyALiquidated(partyA)).to.equal(false)

			// Second insolvency after cleanup — leftover symbolsPrices still timestamp=reusedTimestamp.
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))
			const open2 = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), partyA))
			await hedger.lockQuote(open2, 0n, null)
			await hedger.openPosition(open2)

			const price2 = decimal(9n) // different mark than leftover storage price
			const upnl = await user.getUpnl(async () => price2)
			const totalUnrealizedLoss = await user.getTotalUnrealisedLoss(async () => price2)
			const allocatedBalance = (await user.getBalanceInfo()).allocatedBalances
			const secondSig = await getDummyLiquidationSig(
				"0x22",
				upnl,
				[1n],
				[price2],
				totalUnrealizedLoss,
				allocatedBalance,
			)
			secondSig.timestamp = reusedTimestamp
			secondSig.liquidationTimestamp = reusedTimestamp

			const now = await getBlockTimestamp()
			expect(reusedTimestamp >= now, `timestamp still ahead: reused=${reusedTimestamp} now=${now}`).to.equal(true)

			await runTx(context.liquidationFacet.connect(context.signers.liquidator).liquidatePartyA(partyA, secondSig))
			expect(await context.viewFacet.isPartyALiquidated(partyA)).to.equal(true)

			// BUG fixed: skip setSymbolsPrice — stale timestamp alone must not authorize positions.
			await expect(
				context.liquidationPositionsFacet
					.connect(context.signers.liquidator)
					.liquidatePositionsPartyA(partyA, [open2.quoteId]),
			).to.be.revertedWith("LiquidationFacet: Price should be set")
		})
	})
}
