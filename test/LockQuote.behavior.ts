import {loadFixtureCompatible, timeCompatible} from "./utils/testHelpers"
import {expect} from "chai"

import {initializeFixture} from "./Initialize.fixture"
import {PositionType, QuoteStatus} from "./models/Enums"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {limitQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {LockQuoteValidator} from "./models/validators/LockQuoteValidator"
import {UnlockQuoteValidator} from "./models/validators/UnlockQuoteValidator"
import {decimal, pausePartyB} from "./utils/Common"
import {getDummySingleUpnlSig} from "./utils/SignatureUtils"
import {QuoteStruct} from "../src/types/contracts/interfaces/ISymmio"
import {QuoteData} from "./models/types";

export function shouldBehaveLikeLockQuote(): void {
	let context: RunContext, user: User, hedger: Hedger, hedger2: Hedger
	let quoteDataArray: {[key: string]: QuoteData} = {}

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)
		this.user_allocated = decimal(700n)
		this.hedger_allocated = decimal(4000n)

		user = new User(context, context.signers.user)
		await user.setup()
		await user.setBalances(decimal(2000n), decimal(1000n), this.user_allocated)

		hedger = new Hedger(context, context.signers.hedger)
		await hedger.setup()
		await hedger.setBalances(this.hedger_allocated, this.hedger_allocated)

		hedger2 = new Hedger(context, context.signers.hedger2)
		await hedger2.setup()
		await hedger2.setBalances(this.hedger_allocated, this.hedger_allocated)

		quoteDataArray[1] = await user.sendQuote()
		quoteDataArray[2] = await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())
		quoteDataArray[3] = await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())
		quoteDataArray[4] = await user.sendQuote(
			limitQuoteRequestBuilder()
				.partyBWhiteList([await context.signers.hedger.getAddress()])
				.build(),
		)
		quoteDataArray[5] = await user.sendQuote()
	})

	it("Should fail on invalid quoteId", async function () {
		await expect(hedger.lockQuote({quoteId:6n, partyBEvent: undefined}, 0n, null)).to.be.reverted
	})

	it("Should fail on low balance", async function () {
		await expect(hedger.lockQuote(quoteDataArray[1], 0n, null)).to.be.revertedWith("PartyBFacet: insufficient available balance")
	})

	it("Should fail on low balance (negative upnl)", async function () {
		await expect(hedger.lockQuote(quoteDataArray[1], decimal(-125n))).to.be.revertedWith("PartyBFacet: Available balance is lower than zero")
	})

	it("Should fail on invalid partyB", async function () {
		await expect(context.partyBQuoteActionsFacet.connect(context.signers.user2).lockQuote(quoteDataArray[1].quoteId, await getDummySingleUpnlSig())).to.be.revertedWith(
			"Accessibility: Should be partyB",
		)
	})

	it("Should fail on invalid state", async function () {
		await hedger.lockQuote(quoteDataArray[1])
		await expect(hedger.lockQuote(quoteDataArray[1])).to.be.revertedWith("PartyBFacet: Invalid state")
	})

	it("Should fail on liquidated partyA", async function () {
		await hedger.lockQuote(quoteDataArray[2])
		await hedger.openPosition(quoteDataArray[2])
		await user.liquidateAndSetSymbolPrices([1n], [decimal(200n)])
		await expect(hedger.lockQuote(quoteDataArray[1])).to.be.revertedWith("Accessibility: PartyA isn't solvent")
	})

	it("Should fail on paused partyB", async function () {
		await pausePartyB(context)
		await expect(hedger.lockQuote(quoteDataArray[1])).to.be.revertedWith("Pausable: PartyB actions paused")
	})

	it("Should fail on paused partyB", async function () {
		await expect(hedger2.lockQuote(quoteDataArray[4])).to.be.revertedWith("PartyBFacet: Sender isn't whitelisted")
	})

	it("Should fail on expired quote", async function () {
		await timeCompatible.increase(1000)
		await expect(hedger.lockQuote(quoteDataArray[1])).to.be.revertedWith("PartyBFacet: Quote is expired")
	})

	it("Should run successfully", async function () {
		const validator = new LockQuoteValidator()
		const beforeOut = await validator.before(context, {
			user: user,
		})
		await hedger.lockQuote(quoteDataArray[1])
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: quoteDataArray[1].quoteId,
			beforeOutput: beforeOut,
		})
	})

	describe("Unlock Quote", async function () {
		beforeEach(async function () {
			await hedger.lockQuote(quoteDataArray[1])
		})

		it("Should liquidate on partyB being not the one", async function () {
			await expect(hedger2.unlockQuote(quoteDataArray[1].quoteId)).to.be.revertedWith("Accessibility: Should be partyB of quote")
		})

		it("Should fail on paused partyB", async function () {
			await pausePartyB(context)
			await expect(hedger.unlockQuote(quoteDataArray[1].quoteId)).to.be.revertedWith("Pausable: PartyB actions paused")
		})

		it("Should expire quote during unlock", async function () {
			await timeCompatible.increase(1000)
			await hedger.unlockQuote(quoteDataArray[1].quoteId)
			let q: QuoteStruct = await context.viewFacet.getQuote(1)
			expect(q.quoteStatus).to.be.equal(QuoteStatus.EXPIRED)
		})

		it("Should run successfully", async function () {
			const validator = new UnlockQuoteValidator()
			const beforeOut = await validator.before(context, {user: user})
			await hedger.unlockQuote(quoteDataArray[1].quoteId)
			await validator.after(context, {
				user: user,
				quoteId: quoteDataArray[1].quoteId,
				beforeOutput: beforeOut,
			})
		})
	})
}
