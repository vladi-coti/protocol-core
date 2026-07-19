import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummySingleUpnlSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

const SUSPENDED = "Accessibility: Sender is Suspended"

/**
 * M-10: suspension guards sendQuote/allocate/withdraw but not deallocate or
 * PartyA cancel/close request paths — incomplete freeze.
 */
export function shouldBehaveLikeAuditM10(): void {
	describe("suspension gaps on PartyA state changes", function () {
		it("M-10 static: deallocate and PartyA cancel/close require notSuspended", function () {
			const account = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/Account/AccountFacet.sol"),
				"utf8",
			)
			const dealloc = account.slice(account.indexOf("function deallocate("), account.indexOf("function deallocateWithQuotePrices"))
			expect(dealloc).to.include("notSuspended(msg.sender)")
			const deallocPrices = account.slice(
				account.indexOf("function deallocateWithQuotePrices"),
				account.indexOf("function internalTransfer"),
			)
			expect(deallocPrices).to.include("notSuspended(msg.sender)")

			const partyA = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/PartyA/PartyAFacet.sol"),
				"utf8",
			)
			const cancelQuote = partyA.slice(
				partyA.indexOf("function requestToCancelQuote"),
				partyA.indexOf("function requestToClosePosition"),
			)
			expect(cancelQuote).to.include("notSuspended(msg.sender)")
			const closePos = partyA.slice(
				partyA.indexOf("function requestToClosePosition"),
				partyA.indexOf("function requestToCancelCloseRequest"),
			)
			expect(closePos).to.include("notSuspended(msg.sender)")
			const cancelClose = partyA.slice(partyA.indexOf("function requestToCancelCloseRequest"))
			expect(cancelClose).to.include("notSuspended(msg.sender)")
		})

		it("M-10: suspended PartyA cannot deallocate / cancel quote / close / cancel-close", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			await runTx(context.controlFacet.connect(context.signers.admin).setDeallocateDebounceTime(0))

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(5000n), decimal(3000n), decimal(2000n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(5000n), decimal(5000n))

			const partyA = await user.getAddress()
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(2000n), partyA))

			const pending = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.build(),
			)
			const openClose = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.build(),
			)
			const openForClose = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.build(),
			)
			await hedger.lockQuote(openClose)
			await hedger.openPosition(openClose)
			await hedger.lockQuote(openForClose)
			await hedger.openPosition(openForClose)
			await user.requestToClosePosition(
				openClose.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, openClose.quoteId))
					.closePrice(decimal(1n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			await runTx(context.controlFacet.connect(context.signers.admin).suspendedAddress(partyA))
			expect(await context.viewFacet.isSuspended(partyA)).to.equal(true)

			await expect(
				context.accountFacet.connect(context.signers.user).deallocate(decimal(1n), await getDummySingleUpnlSig()),
			).to.be.revertedWith(SUSPENDED)

			await expect(
				context.partyAFacet.connect(context.signers.user).requestToCancelQuote(pending.quoteId),
			).to.be.revertedWith(SUSPENDED)

			await expect(
				context.partyAFacet.connect(context.signers.user).requestToCancelCloseRequest(openClose.quoteId),
			).to.be.revertedWith(SUSPENDED)

			const [encPrice, encQty, orderType, deadline] = await user.buildCloseRequestCalldataArgs(
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, openForClose.quoteId))
					.closePrice(decimal(1n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)
			await expect(
				context.partyAFacet
					.connect(context.signers.user)
					.requestToClosePosition(openForClose.quoteId, encPrice, encQty, orderType, deadline),
			).to.be.revertedWith(SUSPENDED)
		})
	})
}
