import "../utils/revertedWith"
import { expect } from "chai"
import { EventLog } from "ethers"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { QuoteData } from "../models/types"
import { decimal, getQuoteQuantity } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-23: partial fill creates child quote and emits SendQuoteForPartyA/B,
 * but omits ObserverSendQuote that sendQuote emits for new quotes.
 */
export function shouldBehaveLikeAuditM23(): void {
	describe("partial-fill child observer events", function () {
		it("M-23 static: openPosition child path emits ObserverSendQuote with SendQuote", function () {
			const facet = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyBPositionActions/PartyBPositionActionsFacet.sol"),
				"utf8",
			)
			const childBlock = facet.slice(facet.indexOf("if (newId != 0)"), facet.lastIndexOf("}"))
			expect(childBlock).to.match(/emit\s+SendQuoteForPartyA/)
			expect(childBlock).to.match(/emit\s+ObserverSendQuote/)

			const group = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyBGroupActions/PartyBGroupActionsFacet.sol"),
				"utf8",
			)
			const groupChild = group.slice(group.indexOf("if (newId != 0)"), group.lastIndexOf("}"))
			expect(groupChild).to.match(/emit\s+ObserverSendQuote/)
		})

		it("M-23: partial open emits ObserverSendQuote for child quoteId", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const quoteData: QuoteData = await user.sendQuote()
			await hedger.lockQuote(quoteData)

			const quantity = await getQuoteQuantity(context, quoteData.quoteId)
			const filledAmount = quantity / 4n
			const openRequest = limitOpenRequestBuilder()
				.filledAmount(filledAmount)
				.openPrice(decimal(1n))
				.price(decimal(1n))
				.build()
			const { encryptedParams, upnlSig } = await hedger.buildOpenPositionCalldataArgs(
				openRequest,
				undefined,
				quoteData.quoteId,
				await user.getAddress(),
			)

			const receipt = await runTx(
				context.partyBPositionActionsFacet
					.connect(context.signers.hedger)
					.openPosition(quoteData.quoteId, encryptedParams, upnlSig),
			)

			const sendPartyA = receipt.logs.filter(
				(log: any): log is EventLog => (log as EventLog).eventName === "SendQuoteForPartyA",
			)
			const observerSend = receipt.logs.filter(
				(log: any): log is EventLog => (log as EventLog).eventName === "ObserverSendQuote",
			)

			expect(sendPartyA.length).to.be.greaterThan(0)
			const childId = sendPartyA[0].args[1]
			expect(observerSend.some((e: EventLog) => e.args[1] === childId)).to.equal(
				true,
				"ObserverSendQuote missing for partial-fill child quote",
			)
		})
	})
}
