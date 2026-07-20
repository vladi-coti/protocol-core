import "../utils/revertedWith"
import { expect } from "chai"
import { EventLog } from "ethers"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { decimal } from "../utils/Common"
import { getDummyPairUpnlAndPriceSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-24: EmergencyClosePosition emits plaintext closedPrice (= Muon upnlSig.price).
 * Accepted under H-01 path C — Muon mark is already public in calldata; encrypting
 * the event alone is theater. Force/fill stay encrypted for different reasons
 * (computed/private close prices), not because emergency should match them.
 */
export function shouldBehaveLikeAuditM24(): void {
	describe("emergency close price event privacy", function () {
		it("M-24 static: EmergencyClosePosition closedPrice stays public uint256 (intentional)", function () {
			const events = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyBPositionActions/IPartyBPositionActionsEvents.sol"),
				"utf8",
			)
			const block = events.slice(
				events.indexOf("event EmergencyClosePosition"),
				events.indexOf(";", events.indexOf("event EmergencyClosePosition")) + 1,
			)
			expect(block).to.match(/uint256\s+closedPrice/)
			expect(block).to.not.match(/ctUint256\s+closedPrice/)
			expect(block).to.match(/ctUint256\s+filledAmount/)

			const facet = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/RecoveryActions/RecoveryActionsFacet.sol"),
				"utf8",
			)
			const emitBlock = facet.slice(
				facet.indexOf("function emergencyClosePosition"),
				facet.lastIndexOf("}"),
			)
			expect(emitBlock).to.match(/emit\s+EmergencyClosePosition\([\s\S]*upnlSig\.price/)
		})

		it("M-24: EmergencyClosePosition log closedPrice equals Muon sig price (public)", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), await user.getAddress()))

			const open = await user.sendQuote()
			await hedger.lockQuote(open)
			await hedger.openPosition(open)

			await runTx(context.controlFacet.connect(context.signers.admin).setPartyBEmergencyStatus([await hedger.getAddress()], true))

			const closePrice = decimal(1n)
			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			const sig = await getDummyPairUpnlAndPriceSig(closePrice)
			const partyAPositions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
			const partyBPositions = await context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
			;(sig as any).partyAQuoteIds = partyAPositions.map((q: any) => BigInt(q.id))
			;(sig as any).partyAPrices = partyAPositions.map(() => closePrice)
			;(sig as any).partyBQuoteIds = partyBPositions.map((q: any) => BigInt(q.id))
			;(sig as any).partyBPrices = partyBPositions.map(() => closePrice)

			const receipt = await runTx(
				context.recoveryActionsFacet.connect(context.signers.hedger).emergencyClosePosition(open.quoteId, sig),
			)

			const event = receipt.logs.find(
				(log: any): log is EventLog => (log as EventLog).eventName === "EmergencyClosePosition",
			)
			expect(event).to.not.be.undefined

			const closedPriceField = (event as EventLog).args.closedPrice
			expect(closedPriceField).to.equal(closePrice)
		})
	})
}
