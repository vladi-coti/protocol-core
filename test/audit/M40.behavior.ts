import "../utils/revertedWith"
import { expect } from "chai"
import { EventLog } from "ethers"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitFillCloseRequestBuilder } from "../models/requestModels/FillCloseRequest"
import { decimal, decryptUint256, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-40: open/close emit PartyA/B execution events but no Observer* execution events.
 * Observer quote storage still updates via LibEncryption — same polling model as M-14.
 */
export function shouldBehaveLikeAuditM40(): void {
	describe("observer execution event coverage", function () {
		it("M-40 static: no ObserverOpenPosition / ObserverFillClose events in ABI or facets", function () {
			const events = fs.readFileSync(path.join(__dirname, "../../contracts/interfaces/IPartiesEvents.sol"), "utf8")
			expect(events).to.match(/event\s+OpenPositionForPartyA/)
			expect(events).to.match(/event\s+FillCloseRequestForPartyA/)
			expect(events).to.not.match(/event\s+ObserverOpenPosition/)
			expect(events).to.not.match(/event\s+ObserverFillClose/)

			const openFacet = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyBPositionActions/PartyBPositionActionsFacet.sol"),
				"utf8",
			)
			const openFn = openFacet.slice(openFacet.indexOf("function openPosition"), openFacet.indexOf("function acceptCancelRequest"))
			expect(openFn).to.match(/emit\s+OpenPositionForPartyA/)
			expect(openFn).to.not.match(/emit\s+ObserverOpen/)

			const closeFacet = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyBPositionActions/PartyBCloseActionsFacet.sol"),
				"utf8",
			)
			expect(closeFacet).to.match(/emit\s+FillCloseRequestForPartyA/)
			expect(closeFacet).to.not.match(/emit\s+ObserverFill/)
		})

		it("M-40: fillClose emits party execution events only; observer storage still tracks close", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))
			await runTx(
				context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.liquidator.address),
			)

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const observerOpened = await context.viewFacet.getObserverQuote(quote.quoteId)
			const openedPx = await decryptUint256(context, observerOpened.openedPrice, context.signers.liquidator)
			expect(openedPx, "observer storage must track open execution").to.be.gt(0n)

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
			expect(receipt).to.not.be.null

			const partyFill = receipt!.logs.filter(
				(log: any): log is EventLog =>
					(log as EventLog).eventName === "FillCloseRequestForPartyA" ||
					(log as EventLog).eventName === "FillCloseRequestForPartyB",
			)
			const observerFill = receipt!.logs.filter((log: any): log is EventLog =>
				String((log as EventLog).eventName || "").startsWith("ObserverFill"),
			)
			expect(partyFill.length).to.be.greaterThan(0)
			expect(observerFill.length, "no ObserverFill* execution events (poll views)").to.equal(0)

			const observerAfter = await context.viewFacet.getObserverQuote(quote.quoteId)
			const closedAmt = await decryptUint256(context, observerAfter.closedAmount, context.signers.liquidator)
			expect(closedAmt, "observer storage must track close execution").to.equal(qty)
		})
	})
}
