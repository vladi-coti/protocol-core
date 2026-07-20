import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

import { QuoteSettlementDataStructOutput } from "../../src/types/contracts/facets/Settlement/ISettlementFacet"
import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitFillCloseRequestBuilder } from "../models/requestModels/FillCloseRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyPriceSig, getDummySettlementSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

const REALIZED_PNL_IN = 4
const REALIZED_PNL_OUT = 5

const sharedEventsInterface = new ethers.Interface([
	"event BalanceChangePartyA(address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
	"event BalanceChangePartyB(address indexed partyB, address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
])

function pnlTypeShape(receipt: any): string[] {
	return receipt.logs
		.map((log: any) => {
			try {
				return sharedEventsInterface.parseLog(log)
			} catch {
				return null
			}
		})
		.filter(
			(e: any) =>
				e &&
				(e.name === "BalanceChangePartyA" || e.name === "BalanceChangePartyB") &&
				(Number(e.args._type) === REALIZED_PNL_IN || Number(e.args._type) === REALIZED_PNL_OUT),
		)
		.map((e: any) => `${e.name}:${Number(e.args._type)}`)
}

/**
 * M-34: LibQuote close emits constant IN+OUT shape (one encrypted zero).
 * LibSettlement / PartyA liquidation branch and emit only the matching direction → public PnL leak.
 */
export function shouldBehaveLikeAuditM34(): void {
	describe("PnL event direction privacy", function () {
		it("M-34 static: settlement/liquidation PnL paths dual-emit IN+OUT like LibQuote", function () {
			const quote = fs.readFileSync(path.join(__dirname, "../../contracts/libraries/LibQuote.sol"), "utf8")
			const closePnl = quote.slice(quote.indexOf("gtPartyAPnlIn"), quote.indexOf("Update avgClosedPrice"))
			expect(closePnl.match(/REALIZED_PNL_IN/g)?.length).to.equal(2)
			expect(closePnl.match(/REALIZED_PNL_OUT/g)?.length).to.equal(2)

			const settlement = fs.readFileSync(path.join(__dirname, "../../contracts/libraries/LibSettlement.sol"), "utf8")
			expect(settlement).to.match(/gtPartyBPnlIn/)
			expect(settlement).to.match(/gtPartyBPnlOut/)
			expect(settlement).to.match(/gtPartyAPnlIn/)
			expect(settlement).to.match(/gtPartyAPnlOut/)
			expect((settlement.match(/REALIZED_PNL_IN/g) || []).length).to.be.greaterThanOrEqual(2)
			expect((settlement.match(/REALIZED_PNL_OUT/g) || []).length).to.be.greaterThanOrEqual(2)

			const liq = fs.readFileSync(path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"), "utf8")
			const settleLoop = liq.slice(liq.indexOf("gtSettleAmount.lt"), liq.indexOf("involvedPartyBCounts == 0"))
			expect((settleLoop.match(/REALIZED_PNL_IN/g) || []).length).to.be.greaterThanOrEqual(2)
			expect((settleLoop.match(/REALIZED_PNL_OUT/g) || []).length).to.be.greaterThanOrEqual(2)
		})

		it("M-34: fillClose keeps constant PartyA/PartyB IN+OUT shape", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const qty = await getQuoteQuantity(context, quote.quoteId)
			await user.requestToClosePosition(
				quote.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(qty)
					.closePrice(decimal(2n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			const fillReq = limitFillCloseRequestBuilder().filledAmount(qty).closedPrice(decimal(2n)).build()
			const { encryptedParams, upnlSig } = await hedger.buildFillCloseRequestCalldataArgs(fillReq)
			const partyAPositions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
			const partyBPositions = await context.viewFacet.getPartyBOpenPositions(await hedger.getAddress(), partyA, 0, 100)
			;(upnlSig as any).partyAQuoteIds = partyAPositions.map((q: any) => BigInt(q.id))
			;(upnlSig as any).partyAPrices = partyAPositions.map(() => BigInt(fillReq.price))
			;(upnlSig as any).partyBQuoteIds = partyBPositions.map((q: any) => BigInt(q.id))
			;(upnlSig as any).partyBPrices = partyBPositions.map(() => BigInt(fillReq.price))

			const tx = await context.partyBCloseActionsFacet
				.connect(context.signers.hedger)
				.fillCloseRequest(quote.quoteId, encryptedParams, upnlSig)
			const receipt = await tx.wait()
			expect(pnlTypeShape(receipt)).to.deep.equal([
				"BalanceChangePartyA:4",
				"BalanceChangePartyA:5",
				"BalanceChangePartyB:4",
				"BalanceChangePartyB:5",
			])
		})

		it("M-34: settleUpnl uses constant PartyA/PartyB IN+OUT shape", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(20000n), decimal(10000n), decimal(5000n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(20000n), decimal(20000n))
			await runTx(
				context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(5000n), await user.getAddress()),
			)

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			const mark = decimal(1n)
			const partyAPositions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
			const partyBPositions = await context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
			const partyAPriceSig = await getDummyPriceSig(
				partyAPositions.map((q: any) => BigInt(q.id)),
				partyAPositions.map(() => mark),
			)
			const partyBPriceSig = await getDummyPriceSig(
				partyBPositions.map((q: any) => BigInt(q.id)),
				partyBPositions.map(() => mark),
			)

			// LONG mark down (updated < opened): PartyA loses → only OUT; PartyB only IN (direction leak).
			const updatedPrices = [decimal(5n, 17)]
			const settlementSig = await getDummySettlementSig(0n, [0n], [
				{
					quoteId: quote.quoteId,
					currentPrice: 0n,
				} as QuoteSettlementDataStructOutput,
			])
			;(settlementSig as any).partyAPriceSig = partyAPriceSig
			;(settlementSig as any).partyBPriceSigs = [partyBPriceSig]

			const tx = await context.settlementFacet
				.connect(context.signers.hedger)
				.settleUpnl(settlementSig, updatedPrices, partyA)
			const receipt = await tx.wait()
			expect(pnlTypeShape(receipt)).to.deep.equal([
				"BalanceChangePartyB:4",
				"BalanceChangePartyB:5",
				"BalanceChangePartyA:4",
				"BalanceChangePartyA:5",
			])
		})
	})
}
