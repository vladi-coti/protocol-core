import { expect } from "chai"
import { ethers } from "hardhat"
import { Wallet } from "@coti-io/coti-ethers"
import { initializeFixture } from "./Initialize.fixture"
import { RunContext } from "./models/RunContext"
import { PrivateUser, PrivateQuoteRequest } from "./models/PrivateUser"
import { Hedger } from "./models/Hedger"
import { decimal } from "./utils/Common"
import { getDummySingleUpnlAndPriceSig } from "./utils/SignatureUtils"
import { loadFixtureCompatible } from "./utils/testHelpers"
import { setupAccounts } from "./utils/accounts"

export function shouldBehaveLikeSendPrivateQuote(): void {
	let context: RunContext
	let privateUser: PrivateUser
	let privateUser2: PrivateUser
	let hedger: Hedger
	let userWallet: Wallet
	let user2Wallet: Wallet

	let createDefaultPrivateQuoteRequest: () => PrivateQuoteRequest

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)

		// Setup private wallets using Coti accounts
		const accounts = await setupAccounts()
		userWallet = accounts[1]
		user2Wallet = accounts[2]

		privateUser = new PrivateUser(context, userWallet)
		privateUser2 = new PrivateUser(context, user2Wallet)

		// Setup balances
		await privateUser.setup()
		await privateUser.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

		await privateUser2.setup()
		await privateUser2.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

		// Setup hedger
		hedger = new Hedger(context, context.signers.hedger)
		await hedger.setup()
		await hedger.setBalances(decimal(4000n), decimal(4000n))

		const partyBWhiteList = [await privateUser2.getAddress()]
		createDefaultPrivateQuoteRequest = () => PrivateUser.createDefaultPrivateQuoteRequest(partyBWhiteList)
	})

	describe("Basic Private Quote Functionality", function () {
		it("Should successfully send a private quote", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			const quoteId = await privateUser.sendPrivateQuote(request)
			expect(quoteId).to.be.a("string")
			expect(BigInt(quoteId)).to.be.greaterThan(0)
		})

		it("Should create quote with placeholder values in public storage", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			const quoteId = await privateUser.sendPrivateQuote(request)
			const quote = await context.viewFacet.getQuote(quoteId)

			// Verify placeholder values are used (not actual sensitive data)
			expect(quote.quantity).to.equal(1n) // Placeholder value
			expect(quote.requestedOpenPrice).to.equal(1n) // Placeholder value
			expect(quote.lockedValues.cva).to.equal(1n) // Placeholder value
			expect(quote.lockedValues.lf).to.equal(1n) // Placeholder value
			expect(quote.lockedValues.partyAmm).to.equal(1n) // Placeholder value
			expect(quote.lockedValues.partyBmm).to.equal(1n) // Placeholder value
		})
	})

	describe("Storage Privacy Tests", function () {
		it("Should not store plaintext values in contract storage", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			const quoteId = await privateUser.sendPrivateQuote(request)
			const quote = await context.viewFacet.getQuote(quoteId)

			// Ensure actual values are NOT stored in plaintext
			expect(quote.quantity).to.not.equal(request.quantity)
			expect(quote.requestedOpenPrice).to.not.equal(request.price)
			expect(quote.lockedValues.cva).to.not.equal(request.cva)
			expect(quote.lockedValues.lf).to.not.equal(request.lf)
			expect(quote.lockedValues.partyAmm).to.not.equal(request.partyAmm)
			expect(quote.lockedValues.partyBmm).to.not.equal(request.partyBmm)

			// Ensure placeholder values are used instead
			expect(quote.quantity).to.equal(1n)
			expect(quote.requestedOpenPrice).to.equal(1n)
			expect(quote.lockedValues.cva).to.equal(1n)
			expect(quote.lockedValues.lf).to.equal(1n)
			expect(quote.lockedValues.partyAmm).to.equal(1n)
			expect(quote.lockedValues.partyBmm).to.equal(1n)
		})
	})

	describe("Access Control and Validation", function () {
		it("Should enforce deadline validation", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.deadline = Promise.resolve(BigInt(Math.floor(Date.now() / 1000) - 1000)) // Past deadline
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			await expect(privateUser.sendPrivateQuote(request)).to.be.revertedWith("PartyAFacet: Low deadline")
		})

		it("Should validate partyB whitelist", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.partyBWhiteList = [await privateUser.getAddress()] // PartyA cannot be in whitelist
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			await expect(privateUser.sendPrivateQuote(request)).to.be.revertedWith("PartyAFacet: Sender isn't allowed in partyBWhiteList")
		})

		it("Should validate symbol ID", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.symbolId = 999999n // Invalid symbol ID
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			await expect(privateUser.sendPrivateQuote(request)).to.be.revertedWith("PartyAFacet: Symbol is not valid")
		})
	})

	describe("State Consistency", function () {
		it("Should maintain consistent state between public and private storage", async function () {
			const request = createDefaultPrivateQuoteRequest()
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			const quoteId = await privateUser.sendPrivateQuote(request)
			const quote = await context.viewFacet.getQuote(quoteId)

			// Verify quote state is consistent
			expect(quote.partyA).to.equal(await privateUser.getAddress())
			expect(quote.partyB).to.equal(ethers.ZeroAddress)
			expect(quote.symbolId).to.equal(request.symbolId)
			expect(quote.positionType).to.equal(request.positionType)
			expect(quote.orderType).to.equal(request.orderType)
			expect(quote.maxFundingRate).to.equal(request.maxFundingRate)
			expect(quote.affiliate).to.equal(request.affiliate)
		})

		it("Should properly handle trading fee deduction", async function () {
			const initialBalance = await privateUser.getBalanceInfo()

			const request = createDefaultPrivateQuoteRequest()
			request.upnlSig = await getDummySingleUpnlAndPriceSig(BigInt(request.price.toString()), 0n)

			await privateUser.sendPrivateQuote(request)

			const finalBalance = await privateUser.getBalanceInfo()

			// Trading fee should be deducted from allocated balance
			expect(finalBalance.allocatedBalances).to.be.lessThan(initialBalance.allocatedBalances)
		})
	})
}
