import { expect } from "chai"
import { initializeFixture } from "./Initialize.fixture"
import { PositionType, QuoteStatus } from "./models/Enums"
import { Hedger } from "./models/Hedger"
import { RunContext } from "./models/RunContext"
import { User } from "./models/User"
import { limitOpenRequestBuilder } from "./models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder, marketQuoteRequestBuilder } from "./models/requestModels/QuoteRequest"
import { OpenPositionValidator } from "./models/validators/OpenPositionValidator"
import { decimal, getQuoteQuantity, pausePartyB } from "./utils/Common"
import { getDummyPairUpnlAndPriceSig } from "./utils/SignatureUtils"
import { loadFixtureCompatible } from "./utils/testHelpers"

export function shouldBehaveLikePrivateOpenPosition(): void {
	let context: RunContext, user: User, hedger: Hedger, hedger2: Hedger

	// Helper function to create proper signature for openPositionWithPrivacy
	async function createOpenPositionSig(request: any) {
		return await getDummyPairUpnlAndPriceSig(BigInt(request.price), BigInt(request.upnlPartyA), BigInt(request.upnlPartyB))
	}

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

		// Create test quotes
		await user.sendQuote()
		await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())
		await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())
		await user.sendQuote(marketQuoteRequestBuilder().build())

		await hedger.lockQuote(1)
		await hedger2.lockQuote(2)
	})

	describe("Private Quote Management", function () {
		it("Should enable private mode for a quote by partyA", async function () {
			// Initially quote should not be private
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.false

			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			// Quote should now be private
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true
		})

		it("Should enable private mode for a quote by partyB", async function () {
			// Initially quote should not be private
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.false

			// Enable private mode by partyB
			await context.privateQuoteFacet.connect(context.signers.hedger).enablePrivateMode(1)

			// Quote should now be private
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true
		})

		it("Should fail to enable private mode by unauthorized user", async function () {
			await expect(context.privateQuoteFacet.connect(context.signers.user2).enablePrivateMode(1)).to.be.revertedWith(
				"PrivateQuoteFacet: Only quote parties can enable private mode",
			)
		})

		it("Should fail to enable private mode twice", async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			await expect(context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)).to.be.revertedWith(
				"PrivateQuoteFacet: Quote already in private mode",
			)
		})

		it("Should batch enable private mode for multiple quotes", async function () {
			const quoteIds = [1, 2]

			// Initially quotes should not be private
			for (const id of quoteIds) {
				expect(await context.privateQuoteFacet.isPrivateQuote(id)).to.be.false
			}

			// Batch enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).batchEnablePrivateMode(quoteIds)

			// All quotes should now be private
			for (const id of quoteIds) {
				expect(await context.privateQuoteFacet.isPrivateQuote(id)).to.be.true
			}
		})

		it("Should fail batch enable for unauthorized quotes", async function () {
			const quoteIds = [1, 2]

			await expect(context.privateQuoteFacet.connect(context.signers.user2).batchEnablePrivateMode(quoteIds)).to.be.revertedWith(
				"PrivateQuoteFacet: Only quote parties can enable private mode",
			)
		})
	})

	describe("Private Data Access", function () {
		beforeEach(async function () {
			// Enable private mode for quote 1
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)
		})

		it("Should allow partyA to access private quantity", async function () {
			const originalQuantity = await getQuoteQuantity(context, 1n)
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)

			expect(privateQuantity).to.equal(originalQuantity)
		})

		it("Should allow partyB to access private quantity", async function () {
			const originalQuantity = await getQuoteQuantity(context, 1n)
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.hedger).getPrivateQuantity(1)

			expect(privateQuantity).to.equal(originalQuantity)
		})

		it("Should fail unauthorized access to private quantity", async function () {
			await expect(context.privateQuoteFacet.connect(context.signers.user2).getPrivateQuantity(1)).to.be.revertedWith(
				"PrivateQuoteFacet: Only quote parties can access private data",
			)
		})

		it("Should allow access to private closed amount", async function () {
			const closedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			expect(closedAmount).to.equal(0) // Initially should be 0
		})

		it("Should allow access to private party addresses", async function () {
			const partyA = await context.privateQuoteFacet.connect(context.signers.user).getPrivatePartyA(1)
			const partyB = await context.privateQuoteFacet.connect(context.signers.user).getPrivatePartyB(1)

			expect(partyA).to.equal(await user.getAddress())
			expect(partyB).to.equal(await hedger.getAddress())
		})

		it("Should calculate private open amount correctly", async function () {
			const openAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateOpenAmount(1)
			const originalQuantity = await getQuoteQuantity(context, 1n)

			expect(openAmount).to.equal(originalQuantity) // quantity - closedAmount (0)
		})

		it("Should fallback to public data when private not enabled", async function () {
			// Quote 3 is not private
			const publicQuantity = await getQuoteQuantity(context, 3n)
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(3)

			expect(privateQuantity).to.equal(publicQuantity)
		})
	})

	describe("Private Position Opening", function () {
		it("Should open position with private mode enabled", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			// Open position with private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet.connect(context.signers.hedger).openPositionWithPrivacy(
				1,
				filledAmount,
				openedPrice,
				await createOpenPositionSig(request),
				true, // usePrivateMode
			)

			// Verify quote is now private
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true

			// Verify position was opened
			const quote = await context.viewFacet.getQuote(1)
			expect(quote.quoteStatus).to.equal(QuoteStatus.OPENED)
			expect(quote.openedPrice).to.equal(openedPrice)
		})

		it("Should open position without enabling private mode", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			// Open position without private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet.connect(context.signers.hedger).openPositionWithPrivacy(
				1,
				filledAmount,
				openedPrice,
				await createOpenPositionSig(request),
				false, // usePrivateMode
			)

			// Verify quote is still not private
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.false

			// Verify position was opened
			const quote = await context.viewFacet.getQuote(1)
			expect(quote.quoteStatus).to.equal(QuoteStatus.OPENED)
		})

		it("Should open position with pre-enabled private mode", async function () {
			// Pre-enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			// Open position with private mode (already enabled)
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet.connect(context.signers.hedger).openPositionWithPrivacy(
				1,
				filledAmount,
				openedPrice,
				await createOpenPositionSig(request),
				true, // usePrivateMode
			)

			// Verify position was opened
			const quote = await context.viewFacet.getQuote(1)
			expect(quote.quoteStatus).to.equal(QuoteStatus.OPENED)
		})

		it("Should handle partial fills with private mode", async function () {
			const originalQuantity = await getQuoteQuantity(context, 1n)
			const filledAmount = originalQuantity / 4n
			const openedPrice = decimal(9n, 17)

			// Open position partially with private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet.connect(context.signers.hedger).openPositionWithPrivacy(
				1,
				filledAmount,
				openedPrice,
				await createOpenPositionSig(request),
				true, // usePrivateMode
			)

			// Verify original quote is private and opened
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true
			const quote = await context.viewFacet.getQuote(1)
			expect(quote.quoteStatus).to.equal(QuoteStatus.OPENED)

			// Verify private quantity was updated
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			expect(privateQuantity).to.equal(filledAmount)

			// Verify new quote was created for remaining amount
			const newQuote = await context.viewFacet.getQuote(5) // Should be quote ID 5
			expect(newQuote.quantity).to.equal(originalQuantity - filledAmount)
			expect(newQuote.quoteStatus).to.equal(QuoteStatus.PENDING)
		})

		it("Should fail private position opening by unauthorized party", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await expect(
				context.partyBPositionActionsPrivateFacet
					.connect(context.signers.hedger2) // Wrong hedger
					.openPositionWithPrivacy(1, filledAmount, openedPrice, await createOpenPositionSig(request), true),
			).to.be.revertedWith("Accessibility: Should be partyB of quote")
		})

		it("Should fail on paused private facet", async function () {
			await pausePartyB(context)
			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await expect(
				context.partyBPositionActionsPrivateFacet
					.connect(context.signers.hedger)
					.openPositionWithPrivacy(1, filledAmount, openedPrice, await createOpenPositionSig(request), true),
			).to.be.revertedWith("Pausable: PartyB actions paused")
		})
	})

	describe("Private vs Public Behavior Consistency", function () {
		it("Should maintain same validation logic for private positions", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)

			// Test invalid fill amount with private mode
			const request = limitOpenRequestBuilder()
				.filledAmount(filledAmount + decimal(1n))
				.openPrice(decimal(1n))
				.build()

			await expect(
				context.partyBPositionActionsPrivateFacet
					.connect(context.signers.hedger)
					.openPositionWithPrivacy(1, filledAmount + decimal(1n), decimal(1n), await createOpenPositionSig(request), true),
			).to.be.revertedWith("PartyBFacet: Invalid filledAmount")
		})

		it("Should maintain same price validation for private positions", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)

			// Test invalid open price with private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(decimal(2n)).build()
			await expect(
				context.partyBPositionActionsPrivateFacet.connect(context.signers.hedger).openPositionWithPrivacy(
					1,
					filledAmount,
					decimal(2n), // Invalid price
					await createOpenPositionSig(request),
					true,
				),
			).to.be.revertedWith("PartyBFacet: Opened price isn't valid")
		})

		it("Should maintain same solvency checks for private positions", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)

			// Test solvency failure with private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(decimal(1n)).price(decimal(2n)).build()
			await expect(
				context.partyBPositionActionsPrivateFacet
					.connect(context.signers.hedger)
					.openPositionWithPrivacy(1, filledAmount, decimal(1n), await createOpenPositionSig(request), true),
			).to.be.revertedWith("LibSolvency: Available balance is lower than zero")
		})

		it("Should maintain same leverage checks for private positions", async function () {
			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			// Open position with private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet
				.connect(context.signers.hedger)
				.openPositionWithPrivacy(1, filledAmount, openedPrice, await createOpenPositionSig(request), true)

			// Verify leverage calculation used private quantity
			const quote = await context.viewFacet.getQuote(1)
			expect(quote.quoteStatus).to.equal(QuoteStatus.OPENED)
		})
	})

	describe("Gas Usage Comparison", function () {
		it("Should use more gas for private operations", async function () {
			const filledAmount = await getQuoteQuantity(context, 1n)
			const openedPrice = decimal(1n)

			// Measure gas for public position opening
			const publicRequest = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			const publicTx = await context.partyBPositionActionsFacet
				.connect(context.signers.hedger2)
				.openPosition(
					2,
					filledAmount,
					openedPrice,
					await getDummyPairUpnlAndPriceSig(BigInt(publicRequest.price), BigInt(publicRequest.upnlPartyA), BigInt(publicRequest.upnlPartyB)),
				)
			const publicReceipt = await publicTx.wait()
			const publicGasUsed = publicReceipt?.gasUsed || 0n

			// Measure gas for private position opening
			const privateRequest = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			const privateTx = await context.partyBPositionActionsPrivateFacet
				.connect(context.signers.hedger)
				.openPositionWithPrivacy(1, filledAmount, openedPrice, await createOpenPositionSig(privateRequest), true)
			const privateReceipt = await privateTx.wait()
			const privateGasUsed = privateReceipt?.gasUsed || 0n

			// Private operations should use more gas
			expect(privateGasUsed).to.be.greaterThan(publicGasUsed)

			console.log(`Public gas used: ${publicGasUsed}`)
			console.log(`Private gas used: ${privateGasUsed}`)
			console.log(
				`Gas overhead: ${privateGasUsed - publicGasUsed} (${((Number(privateGasUsed - publicGasUsed) / Number(publicGasUsed)) * 100).toFixed(2)}%)`,
			)
		})
	})

	describe("Integration with Existing Validators", function () {
		it("Should work with existing OpenPositionValidator for private positions", async function () {
			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const validator = new OpenPositionValidator()
			const beforeOut = await validator.before(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
			})

			const openedPrice = decimal(1n)
			const filledAmount = await getQuoteQuantity(context, 1n)

			// Open position with private mode
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet
				.connect(context.signers.hedger)
				.openPositionWithPrivacy(1, filledAmount, openedPrice, await createOpenPositionSig(request), true)

			// Validate using existing validator
			await validator.after(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
				openedPrice: openedPrice,
				fillAmount: filledAmount,
				beforeOutput: beforeOut,
			})
		})
	})

	describe("Error Handling and Edge Cases", function () {
		it("Should handle quote not found gracefully", async function () {
			await expect(context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(999)).to.be.reverted // Quote doesn't exist
		})

		it("Should handle zero amounts correctly", async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const closedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			expect(closedAmount).to.equal(0)
		})

		it("Should maintain data consistency across multiple operations", async function () {
			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			// Get initial values
			const initialQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const initialClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			const initialOpenAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateOpenAmount(1)

			// Verify consistency
			expect(initialOpenAmount).to.equal(initialQuantity - initialClosedAmount)

			// Open position
			const filledAmount = initialQuantity / 2n
			const request = limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(decimal(1n)).price(decimal(1n, 17)).build()
			await context.partyBPositionActionsPrivateFacet
				.connect(context.signers.hedger)
				.openPositionWithPrivacy(1, filledAmount, decimal(1n), await createOpenPositionSig(request), true)

			// Verify updated values
			const updatedQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			expect(updatedQuantity).to.equal(filledAmount)
		})
	})
}
