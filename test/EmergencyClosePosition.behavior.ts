import {loadFixtureCompatible} from "./utils/testHelpers"
import {expect} from "chai"

import {initializeFixture} from "./Initialize.fixture"
import {PositionType} from "./models/Enums"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {limitQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {decimal, pausePartyB,} from "./utils/Common"
import {emergencyCloseRequestBuilder} from "./models/requestModels/EmergencyCloseRequest"
import {EmergencyCloseRequestValidator} from "./models/validators/EmergencyCloseRequestValidator"
import {QuoteData} from "./models/types";

export function shouldBehaveLikeEmergencyClosePosition(): void {
	let user: User, hedger: Hedger, hedger2: Hedger
	let context: RunContext
	let quoteDataArray: {[key: string]: QuoteData} = {}

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)
		this.user_allocated = decimal(500n)
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

		// Quote1 LONG opened

		quoteDataArray[1] = await user.sendQuote()
		await hedger.lockQuote(quoteDataArray[1])
		await hedger.openPosition(quoteDataArray[1])

		// Quote2 SHORT opened
		quoteDataArray[2] = await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())
		await hedger.lockQuote(quoteDataArray[2])
		await hedger.openPosition(quoteDataArray[2])

		// Quote3 SHORT sent
		quoteDataArray[3] = await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())

		// Quote4 LONG sent
		quoteDataArray[4] = await user.sendQuote()
		await hedger.lockQuote(quoteDataArray[4])
		await hedger.openPosition(quoteDataArray[4])
	})


	describe("Emergency Close", async function () {
		beforeEach(async function () {
		})

		it("Should fail when not emergency mode", async function () {
			await expect(hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().build()))
				.to.be.revertedWith("PartyBFacet: Operation not allowed. Either emergency mode must be active, party B must be in emergency status, or the symbol must be delisted")
		})

		describe("Emergency status for partyB activated", async function () {
			beforeEach(async function () {
				await context.controlFacet.setPartyBEmergencyStatus([await hedger2.getAddress()], true)
				await context.controlFacet.setPartyBEmergencyStatus([await hedger.getAddress()], true)
			})

			it("Should fail on invalid partyB", async function () {
				await expect(hedger2.emergencyClosePosition(1, emergencyCloseRequestBuilder().build())).to.be.revertedWith(
					"Accessibility: Should be partyB of quote",
				)
			})

			it("Should fail on paused partyB", async function () {
				await pausePartyB(context)
				await expect(hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().build())).to.be.revertedWith("Pausable: PartyB actions paused")
			})

			it("Should fail on negative balance of partyA/partyB", async function () {
				await expect(hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().upnlPartyA(decimal(-575n)).build())).to.be.revertedWith(
					"PartyBFacet: PartyA is insolvent",
				)
				await expect(hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().upnlPartyB(decimal(-410n)).build())).to.be.revertedWith(
					"PartyBFacet: PartyB should be solvent",
				)
			})

			it("Should run successfully", async function () {
				const validator = new EmergencyCloseRequestValidator()
				const beforeOut = await validator.before(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
				})
				await hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().build())
				await validator.after(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
					price: decimal(1n),
					beforeOutput: beforeOut,
				})
			})
		})


		describe("Emergency mode get activated", async function () {
			beforeEach(async function () {
				await context.controlFacet.activeEmergencyMode()
			})

			it("Should run successfully", async function () {
				const validator = new EmergencyCloseRequestValidator()
				const beforeOut = await validator.before(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
				})
				await hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().build())
				await validator.after(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
					price: decimal(1n),
					beforeOutput: beforeOut,
				})
			})
		})

		describe("Symbol gets deListed", async function () {
			beforeEach(async function () {
				await context.controlFacet.setSymbolValidationState((await context.viewFacet.getQuote(1)).symbolId, false)
			})

			it("Should run successfully", async function () {
				const validator = new EmergencyCloseRequestValidator()
				const beforeOut = await validator.before(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
				})
				await hedger.emergencyClosePosition(1, emergencyCloseRequestBuilder().build())
				await validator.after(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
					price: decimal(1n),
					beforeOutput: beforeOut,
				})
			})
		})
	})
}
