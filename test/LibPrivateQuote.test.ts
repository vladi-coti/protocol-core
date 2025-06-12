import { expect } from "chai"
import { initializeFixture } from "./Initialize.fixture"
import { RunContext } from "./models/RunContext"
import { User } from "./models/User"
import { Hedger } from "./models/Hedger"
import { decimal } from "./utils/Common"
import { limitQuoteRequestBuilder } from "./models/requestModels/QuoteRequest"
import { PositionType } from "./models/Enums"
import { loadFixtureCompatible } from "./utils/testHelpers"

describe("LibPrivateQuote Library", function () {
	let context: RunContext
	let user: User
	let hedger: Hedger

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)

		user = new User(context, context.signers.user)
		await user.setup()
		await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

		hedger = new Hedger(context, context.signers.hedger)
		await hedger.setup()
		await hedger.setBalances(decimal(4000n), decimal(4000n))

		// Create test quotes
		await user.sendQuote()
		await user.sendQuote(limitQuoteRequestBuilder().positionType(PositionType.SHORT).build())

		await hedger.lockQuote(1)
		await hedger.lockQuote(2)
	})

	describe("Private Mode Management", function () {
		it("Should detect non-private quotes correctly", async function () {
			const isPrivate = await context.privateQuoteFacet.isPrivateQuote(1)
			expect(isPrivate).to.be.false
		})

		it("Should enable private mode and detect it", async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const isPrivate = await context.privateQuoteFacet.isPrivateQuote(1)
			expect(isPrivate).to.be.true
		})

		it("Should copy public values to private storage when enabling", async function () {
			const originalQuote = await context.viewFacet.getQuote(1)

			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			// Check that private values match original public values
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const privateClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			const privatePartyA = await context.privateQuoteFacet.connect(context.signers.user).getPrivatePartyA(1)
			const privatePartyB = await context.privateQuoteFacet.connect(context.signers.user).getPrivatePartyB(1)

			expect(privateQuantity).to.equal(originalQuote.quantity)
			expect(privateClosedAmount).to.equal(originalQuote.closedAmount)
			expect(privatePartyA).to.equal(originalQuote.partyA)
			expect(privatePartyB).to.equal(originalQuote.partyB)
		})
	})

	describe("Private Data Retrieval", function () {
		beforeEach(async function () {
			// Enable private mode for quote 1
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)
		})

		it("Should retrieve private quantity correctly", async function () {
			const originalQuote = await context.viewFacet.getQuote(1)
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)

			expect(privateQuantity).to.equal(originalQuote.quantity)
		})

		it("Should retrieve private closed amount correctly", async function () {
			const privateClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)

			expect(privateClosedAmount).to.equal(0) // Initially should be 0
		})

		it("Should retrieve private party addresses correctly", async function () {
			const privatePartyA = await context.privateQuoteFacet.connect(context.signers.user).getPrivatePartyA(1)
			const privatePartyB = await context.privateQuoteFacet.connect(context.signers.user).getPrivatePartyB(1)

			expect(privatePartyA).to.equal(await user.getAddress())
			expect(privatePartyB).to.equal(await hedger.getAddress())
		})

		it("Should calculate open amount correctly", async function () {
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const privateClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			const privateOpenAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateOpenAmount(1)

			expect(privateOpenAmount).to.equal(privateQuantity - privateClosedAmount)
		})

		it("Should fallback to public data for non-private quotes", async function () {
			// Quote 2 is not private
			const originalQuote = await context.viewFacet.getQuote(2)
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(2)

			expect(privateQuantity).to.equal(originalQuote.quantity)
		})
	})

	describe("Access Control", function () {
		beforeEach(async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)
		})

		it("Should allow partyA to access private data", async function () {
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			expect(privateQuantity).to.be.a("bigint")
		})

		it("Should allow partyB to access private data", async function () {
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.hedger).getPrivateQuantity(1)
			expect(privateQuantity).to.be.a("bigint")
		})

		it("Should deny unauthorized access to private data", async function () {
			await expect(context.privateQuoteFacet.connect(context.signers.user2).getPrivateQuantity(1)).to.be.revertedWith(
				"PrivateQuoteFacet: Only quote parties can access private data",
			)
		})

		it("Should deny unauthorized private mode enabling", async function () {
			await expect(context.privateQuoteFacet.connect(context.signers.user2).enablePrivateMode(2)).to.be.revertedWith(
				"PrivateQuoteFacet: Only quote parties can enable private mode",
			)
		})
	})

	describe("Batch Operations", function () {
		it("Should batch enable private mode for multiple quotes", async function () {
			const quoteIds = [1, 2]

			// Initially both should be non-private
			for (const id of quoteIds) {
				expect(await context.privateQuoteFacet.isPrivateQuote(id)).to.be.false
			}

			// Batch enable
			await context.privateQuoteFacet.connect(context.signers.user).batchEnablePrivateMode(quoteIds)

			// Both should now be private
			for (const id of quoteIds) {
				expect(await context.privateQuoteFacet.isPrivateQuote(id)).to.be.true
			}
		})

		it("Should handle mixed authorization in batch operations", async function () {
			// Create a quote where user2 is partyA
			const user2 = new User(context, context.signers.user2)
			await user2.setup()
			await user2.setBalances(decimal(2000n), decimal(1000n), decimal(500n))
			await user2.sendQuote()

			const quoteIds = [1, 3] // Quote 1: user is partyA, Quote 3: user2 is partyA

			await expect(context.privateQuoteFacet.connect(context.signers.user).batchEnablePrivateMode(quoteIds)).to.be.revertedWith(
				"PrivateQuoteFacet: Only quote parties can enable private mode",
			)
		})

		it("Should skip already private quotes in batch operations", async function () {
			// Enable private mode for quote 1
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const quoteIds = [1, 2] // Quote 1 already private, Quote 2 not private

			// Should not revert, just skip quote 1
			await context.privateQuoteFacet.connect(context.signers.user).batchEnablePrivateMode(quoteIds)

			// Both should be private now
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true
			expect(await context.privateQuoteFacet.isPrivateQuote(2)).to.be.true
		})
	})

	describe("Data Consistency", function () {
		it("Should maintain consistency between private and public data", async function () {
			const originalQuote = await context.viewFacet.getQuote(1)

			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			// Private data should match public data
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const privateClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)

			expect(privateQuantity).to.equal(originalQuote.quantity)
			expect(privateClosedAmount).to.equal(originalQuote.closedAmount)
		})

		it("Should handle zero values correctly", async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			const privateClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			expect(privateClosedAmount).to.equal(0)
		})

		it("Should maintain data integrity across multiple operations", async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			// Get initial values
			const initialQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const initialClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)
			const initialOpenAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateOpenAmount(1)

			// Verify mathematical relationship
			expect(initialOpenAmount).to.equal(initialQuantity - initialClosedAmount)

			// Values should be consistent across multiple calls
			const secondQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const secondClosedAmount = await context.privateQuoteFacet.connect(context.signers.user).getPrivateClosedAmount(1)

			expect(secondQuantity).to.equal(initialQuantity)
			expect(secondClosedAmount).to.equal(initialClosedAmount)
		})
	})

	describe("Error Handling", function () {
		it("Should handle non-existent quotes gracefully", async function () {
			await expect(context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(999)).to.be.reverted
		})

		it("Should prevent double enabling of private mode", async function () {
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			await expect(context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)).to.be.revertedWith(
				"PrivateQuoteFacet: Quote already in private mode",
			)
		})

		it("Should handle empty batch operations", async function () {
			const emptyQuoteIds: number[] = []

			// Should not revert with empty array
			await context.privateQuoteFacet.connect(context.signers.user).batchEnablePrivateMode(emptyQuoteIds)
		})
	})

	describe("Gas Usage Analysis", function () {
		it("Should measure gas usage for private operations", async function () {
			// Measure gas for enabling private mode
			const enableTx = await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)
			const enableReceipt = await enableTx.wait()

			// Measure gas for accessing private data
			const accessTx = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			const accessReceipt = await accessTx.wait()

			console.log(`Enable private mode gas: ${enableReceipt.gasUsed}`)
			console.log(`Access private data gas: ${accessReceipt.gasUsed}`)

			// Enabling should use more gas than accessing
			expect(enableReceipt.gasUsed).to.be.greaterThan(accessReceipt.gasUsed)
		})

		it("Should compare batch vs individual operations", async function () {
			const quoteIds = [1, 2]

			// Measure individual operations
			const individual1Tx = await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)
			const individual1Receipt = await individual1Tx.wait()

			// Reset for fair comparison (create new quotes)
			await user.sendQuote()
			await user.sendQuote()
			await hedger.lockQuote(3)
			await hedger.lockQuote(4)

			// Measure batch operation
			const batchTx = await context.privateQuoteFacet.connect(context.signers.user).batchEnablePrivateMode([3, 4])
			const batchReceipt = await batchTx.wait()

			console.log(`Individual operation gas: ${individual1Receipt.gasUsed}`)
			console.log(`Batch operation gas (2 quotes): ${batchReceipt.gasUsed}`)

			// Batch should be more efficient per quote
			const batchPerQuote = Number(batchReceipt.gasUsed) / 2
			expect(batchPerQuote).to.be.lessThan(Number(individual1Receipt.gasUsed))
		})
	})

	describe("Integration with Quote Lifecycle", function () {
		it("Should maintain private mode through quote state changes", async function () {
			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true

			// Open position (this changes quote state)
			await hedger.openPosition(1)

			// Should still be private after opening
			expect(await context.privateQuoteFacet.isPrivateQuote(1)).to.be.true

			// Private data should still be accessible
			const privateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			expect(privateQuantity).to.be.a("bigint")
		})

		it("Should handle private mode with partial fills", async function () {
			const originalQuote = await context.viewFacet.getQuote(1)

			// Enable private mode
			await context.privateQuoteFacet.connect(context.signers.user).enablePrivateMode(1)

			// Verify initial private quantity
			const initialPrivateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			expect(initialPrivateQuantity).to.equal(originalQuote.quantity)

			// After opening position, private quantity should be accessible
			await hedger.openPosition(1)

			const finalPrivateQuantity = await context.privateQuoteFacet.connect(context.signers.user).getPrivateQuantity(1)
			expect(finalPrivateQuantity).to.be.a("bigint")
		})
	})
})
