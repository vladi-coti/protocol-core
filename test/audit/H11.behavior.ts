import "../utils/revertedWith"
import { expect } from "chai"
import { ethers, EventLog } from "ethers"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { QuoteSettlementDataStructOutput } from "../../src/types/contracts/facets/Settlement/ISettlementFacet"
import { decimal } from "../utils/Common"
import { getDummyPriceSig, getDummySettlementSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-11: SettleUpnl must not rebroadcast updatedPrices (new openedPrice) in plaintext events.
 * Calldata of settleUpnl still carries the args; the permanent log must not.
 */
export function shouldBehaveLikeAuditH11(): void {
	describe("settlement event opened-price privacy", function () {
		it("H-11: SettleUpnl ABI must not include plaintext updatedPrices", function () {
			const eventsPath = path.join(__dirname, "../../contracts/facets/Settlement/SettlementFacetEvents.sol")
			const src = fs.readFileSync(eventsPath, "utf8")
			const eventBlock = src.slice(src.indexOf("event SettleUpnl"), src.indexOf(";", src.indexOf("event SettleUpnl")) + 1)
			expect(eventBlock).to.include("event SettleUpnl")
			expect(eventBlock).to.not.match(/uint256\s*\[\s*\]\s*updatedPrices/)
		})

		it("H-11: SettleUpnl log must not carry updatedPrices field", async function () {
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

			const event = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "SettleUpnl")
			expect(event).to.not.be.undefined

			const args = event!.args as any
			expect(args.updatedPrices).to.equal(undefined)
			expect(args.partyA).to.equal(partyA)
			expect(args.settlementData[0].quoteId).to.equal(quote.quoteId)

			// Explicit old ABI must fail to parse the new log shape
			const staleIface = new ethers.Interface([
				"event SettleUpnl(tuple(uint256 quoteId,uint256 currentPrice)[] settlementData,uint256[] updatedPrices,address partyA,tuple(uint256 ciphertextHigh,uint256 ciphertextLow) newPartyAAllocatedBalance,tuple(uint256 ciphertextHigh,uint256 ciphertextLow)[] newPartyBsAllocatedBalances)",
			])
			const parsedStale = receipt!.logs
				.map((log) => {
					try {
						return staleIface.parseLog(log)
					} catch {
						return null
					}
				})
				.find((log) => log?.name === "SettleUpnl")
			expect(parsedStale, "stale ABI with updatedPrices must not decode SettleUpnl").to.equal(undefined)
		})
	})
}
