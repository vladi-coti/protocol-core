import {loadFixtureCompatible, timeCompatible} from "./utils/testHelpers"
import {expect} from "chai"
import {EventLog, ethers} from "ethers"
import {initializeFixture} from "./Initialize.fixture"
import {PositionType, QuoteStatus} from "./models/Enums"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {limitOpenRequestBuilder, marketOpenRequestBuilder} from "./models/requestModels/OpenRequest"
import {limitQuoteRequestBuilder, marketQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {OpenPositionValidator} from "./models/validators/OpenPositionValidator"
import {decryptUint256, decimal, getBlockTimestamp, getQuoteQuantity, getTradingFeeForQuoteWithFilledAmount, pausePartyB, unDecimal} from "./utils/Common"
import {getDummyPairUpnlAndPriceSig, getDummySingleUpnlSig} from "./utils/SignatureUtils"
import {QuoteData} from "./models/types";

export function shouldBehaveLikeOpenPosition(): void {
	let context: RunContext, user: User, hedger: Hedger, hedger2: Hedger
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

		quoteDataArray[1] = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).affiliate(context.multiAccount).deadline(getBlockTimestamp(600n)).build())
		quoteDataArray[2] = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger2.address]).affiliate(context.multiAccount).positionType(PositionType.SHORT).build())
		quoteDataArray[3] = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger2.address]).affiliate(context.multiAccount).positionType(PositionType.SHORT).build())
		quoteDataArray[4] = await user.sendQuote(marketQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).affiliate(context.multiAccount).build())

		await hedger.lockQuote(quoteDataArray[1])
		await hedger2.lockQuote(quoteDataArray[2])
	})

	it("Should fail on not being the correct partyB", async function () {
		await expect(hedger.openPosition(quoteDataArray[2])).to.be.revertedWith("Accessibility: Should be partyB of quote")
	})

	it("Should fail on paused partyB", async function () {
		await pausePartyB(context)
		await expect(hedger.openPosition(quoteDataArray[1])).to.be.revertedWith("Pausable: PartyB actions paused")
	})

	it("Should fail on liquidated quote", async function () {
		await hedger2.openPosition(quoteDataArray[2])
		await hedger2.lockQuote(quoteDataArray[3])
		await user.liquidateAndSetSymbolPrices([1n], [decimal(2000n)])
		await expect(hedger2.openPosition(quoteDataArray[3])).to.be.revertedWith("Accessibility: PartyA isn't solvent")
	})

	it("Should fail on invalid fill amount", async function () {
		// more than quantity
		await expect(
			hedger.openPosition(
				quoteDataArray[1],
				limitOpenRequestBuilder()
					.filledAmount((await getQuoteQuantity(context, 1n)) + decimal(1n))
					.openPrice(decimal(1n))
					.build(),
			),
		).to.be.revertedWith("PBF:fill")

		// zero
		await expect(hedger.openPosition(quoteDataArray[1], limitOpenRequestBuilder().filledAmount("0").build())).to.be.revertedWith("PBF:fill")

		// market should get fully filled
		await hedger.lockQuote(quoteDataArray[4])
		await expect(
			hedger.openPosition(
				quoteDataArray[4],
				limitOpenRequestBuilder()
					.filledAmount((await getQuoteQuantity(context, 4n)) - decimal(1n))
					.openPrice(decimal(1n))
					.build(),
			),
		).to.be.revertedWith("PBF:fill")
	})

	it("Should fail on invalid open price", async function () {
		const quantity = await getQuoteQuantity(context, 1n)
		await expect(hedger.openPosition(quoteDataArray[1], limitOpenRequestBuilder().filledAmount(quantity).openPrice(decimal(2n)).build())).to.be.revertedWith(
			"PBF:open px",
		)

		await expect(hedger2.openPosition(quoteDataArray[2], limitOpenRequestBuilder().filledAmount(quantity).openPrice(decimal(5n, 17)).build())).to.be.revertedWith(
			"PBF:open px",
		)
	})

	it("Should fail if PartyB will be liquidatable", async function () {
		await expect(
			hedger.openPosition(
				quoteDataArray[1],
				limitOpenRequestBuilder()
					.filledAmount(await getQuoteQuantity(context, 1n))
					.openPrice(decimal(1n))
					.price(decimal(2n))
					.build(),
			),
		).to.be.revertedWith("LibSolvency: Available balance is lower than zero")

		await expect(
			hedger2.openPosition(
				quoteDataArray[2],
				limitOpenRequestBuilder()
					.filledAmount(await getQuoteQuantity(context, 2n))
					.openPrice(decimal(1n))
					.price(decimal(1n, 17))
					.upnlPartyB(decimal(-20n))
					.build(),
			),
		).to.be.revertedWith("LibSolvency: Available balance is lower than zero")
	})

	it("Should fail if PartyA will become liquidatable", async function () {
		await expect(
			hedger.openPosition(
				quoteDataArray[1],
				limitOpenRequestBuilder()
					.filledAmount(await getQuoteQuantity(context, 1n))
					.openPrice(decimal(1n))
					.price(decimal(1n, 17))
					.upnlPartyA(decimal(-400n))
					.build(),
			),
		).to.be.revertedWith("LibSolvency: Available balance is lower than zero")
		await expect(
			hedger2.openPosition(
				quoteDataArray[2],
				limitOpenRequestBuilder()
					.filledAmount(await getQuoteQuantity(context, 2n))
					.openPrice(decimal(1n))
					.price(decimal(2n))
					.upnlPartyA(decimal(-400n))
					.build(),
			),
		).to.be.revertedWith("LibSolvency: Available balance is lower than zero")
	})

	it("Should fail partially opened position of quote value is low", async function () {
		await expect(
			hedger.openPosition(
				quoteDataArray[1],
				limitOpenRequestBuilder()
					.filledAmount((await getQuoteQuantity(context, 1n)) - decimal(1n))
					.openPrice(decimal(1n))
					.price(decimal(1n, 17))
					.build(),
			),
		).to.be.revertedWith("PBF:value")

		await expect(
			hedger.openPosition(quoteDataArray[1], limitOpenRequestBuilder().filledAmount(decimal(1n)).openPrice(decimal(1n)).price(decimal(1n, 17)).build()),
		).to.be.revertedWith("PBF:value")
	})

	it("Should fail to open expired quote", async function () {
		const quote = await context.viewFacet.getQuote(quoteDataArray[1].quoteId)
		await timeCompatible.setNextBlockTimestamp(quote.deadline + 1n)
		await expect(
			hedger.openPosition(
				quoteDataArray[1],
				limitOpenRequestBuilder()
					.filledAmount(await getQuoteQuantity(context, 1n))
					.openPrice(decimal(1n))
					.price(decimal(1n, 17))
					.build(),
			),
		).to.be.revertedWith("PBF:exp")
	})

	it("OpenPosition - Should run successfully for limit", async function () {
		const validator = new OpenPositionValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
		})
		const openedPrice = decimal(1n)
		const filledAmount = await getQuoteQuantity(context, 1n)
		await hedger.openPosition(quoteDataArray[1], limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
			openedPrice: openedPrice,
			fillAmount: filledAmount,
			beforeOutput: beforeOut,
		})
	})

	it("OpenPosition - Should run successfully partially for limit", async function () {
		await context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.liquidator.address)
		const validator = new OpenPositionValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
		})
		const quantity = quoteDataArray[1].partyBEvent ? await decryptUint256(context, quoteDataArray[1].partyBEvent.values.quantity, context.signers.hedger) : 0n
		const filledAmount = quantity / 4n
		const openedPrice = decimal(9n, 17)
		await hedger.openPosition(quoteDataArray[1], limitOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n, 17)).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
			openedPrice: openedPrice,
			fillAmount: filledAmount,
			beforeOutput: beforeOut,
			newQuoteId: BigInt(5),
			newQuoteTargetStatus: QuoteStatus.PENDING,
		})

		const childObserverQuote = await context.viewFacet.getObserverQuoteValues(5n)
		expect(await context.signers.liquidator.decryptUint256(childObserverQuote.quantity)).to.equal(quantity - filledAmount)
		expect(await context.signers.liquidator.decryptUint256(childObserverQuote.lockedValues.cva)).to.be.greaterThan(0n)
	})

	it("Should emit raw child quote identities while encrypting PartyB values to partyB key on partial open", async function () {
		const quoteData = quoteDataArray[1]
		const quantity = quoteData.partyBEvent
			? await decryptUint256(context, quoteData.partyBEvent.values.quantity, context.signers.hedger)
			: 0n
		const filledAmount = quantity / 4n
		const openRequest = limitOpenRequestBuilder()
			.filledAmount(filledAmount)
			.openPrice(decimal(9n, 17))
			.price(decimal(1n, 17))
			.build()
		const {encryptedParams, upnlSig} = await hedger.buildOpenPositionCalldataArgs(openRequest)

		const tx = await context.partyBPositionActionsFacet
			.connect(context.signers.hedger)
			.openPosition(quoteData.quoteId, encryptedParams, upnlSig)
		const receipt = await tx.wait()

		const partyAEvent = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "SendQuoteForPartyA")
		const partyBEvent = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "SendQuoteForPartyB")

		expect(partyAEvent).to.not.be.undefined
		expect(partyBEvent).to.not.be.undefined

		const partyAArgs = partyAEvent!.args as any[]
		const partyBArgs = partyBEvent!.args as any[]
		const remainingQuantity = quantity - filledAmount

		expect(partyAArgs[0]).to.equal(context.signers.user.address)
		expect(partyBArgs[0]).to.equal(context.signers.user.address)
		expect(partyBArgs[2]).to.equal(context.signers.hedger.address)
		expect(await context.signers.user.decryptUint256(partyAArgs[6].quantity)).to.equal(remainingQuantity)
		expect(await context.signers.hedger.decryptUint256(partyBArgs[6].quantity)).to.equal(remainingQuantity)
	})

	it("OpenPosition - Should run successfully for market", async function () {
		await hedger.lockQuote(quoteDataArray[4])
		const validator = new OpenPositionValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(4),
		})
		const openedPrice = decimal(1n)
		const filledAmount = await getQuoteQuantity(context, 4n)
		await hedger.openPosition(quoteDataArray[4], marketOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n)).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(4),
			openedPrice: openedPrice,
			fillAmount: filledAmount,
			beforeOutput: beforeOut,
		})
	})

	it("Should accrue trading fee to encrypted fee collector balance", async function () {
		await hedger.lockQuote(quoteDataArray[4])
		const openedPrice = decimal(1n)
		const filledAmount = await getQuoteQuantity(context, 4n)
		const expectedTradingFee = await getTradingFeeForQuoteWithFilledAmount(context, 4n, filledAmount)
		const feeCollector = await context.viewFacet.getFeeCollector(context.multiAccount)
		const beforePlainBalance = await context.viewFacet.balanceOf(feeCollector)

		await context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress)
		await hedger.openPosition(quoteDataArray[4], marketOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n)).build())

		expect(await context.viewFacet.balanceOf(feeCollector)).to.equal(beforePlainBalance)
		const encryptedFeeCollectorBalance = await context.viewFacet.feeCollectorBalance(feeCollector)
		const decryptedFeeCollectorBalance = await context.signers.feeCollector.decryptUint256(encryptedFeeCollectorBalance)
		expect(decryptedFeeCollectorBalance).to.equal(expectedTradingFee)

		await context.accountManagementFacet.connect(context.signers.feeCollector).claimFeeCollectorBalance(expectedTradingFee)
		expect(await context.viewFacet.balanceOf(feeCollector)).to.equal(beforePlainBalance + expectedTradingFee)
		const remainingFeeCollectorBalance = await context.viewFacet.feeCollectorBalance(feeCollector)
		expect(await context.signers.feeCollector.decryptUint256(remainingFeeCollectorBalance)).to.equal(0n)
	})

	it("Should keep observer fee collector and quote mirrors fresh when opening", async function () {
		await context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.liquidator.address)
		await hedger.lockQuote(quoteDataArray[4])
		const openedPrice = decimal(1n)
		const filledAmount = await getQuoteQuantity(context, 4n)
		const expectedTradingFee = await getTradingFeeForQuoteWithFilledAmount(context, 4n, filledAmount)
		const feeCollector = await context.viewFacet.getFeeCollector(context.multiAccount)

		await hedger.openPosition(quoteDataArray[4], marketOpenRequestBuilder().filledAmount(filledAmount).openPrice(openedPrice).price(decimal(1n)).build())

		const observerFeeCollectorBalance = await context.viewFacet.observerFeeCollectorBalance(feeCollector)
		expect(await context.signers.liquidator.decryptUint256(observerFeeCollectorBalance)).to.equal(expectedTradingFee)

		const observerQuote = await context.viewFacet.getObserverQuoteValues(4n)
		expect(await context.signers.liquidator.decryptUint256(observerQuote.openedPrice)).to.equal(openedPrice)
		expect(await context.signers.liquidator.decryptUint256(observerQuote.quantity)).to.equal(filledAmount)
		expect(await context.signers.liquidator.decryptUint256(observerQuote.closedAmount)).to.equal(0n)
		expect(await context.signers.liquidator.decryptUint256(observerQuote.lockedValues.cva)).to.be.greaterThan(0n)
	})

	describe("Group Actions", async function () {
		it("Should lock and open quote", async function () {
			const quoteData = quoteDataArray[3]
			const filledAmount = await getQuoteQuantity(context, quoteData.quoteId)
			const openedPrice = decimal(1n)
			const openRequest = limitOpenRequestBuilder()
				.filledAmount(filledAmount)
				.openPrice(openedPrice)
				.build()
			const parentQuote = await context.viewFacet.getQuote(quoteData.quoteId)
			const requestedOpenPrice = await decryptUint256(context, parentQuote.requestedOpenPrice.userCiphertext, context.signers.user)
			const notional = unDecimal(filledAmount * requestedOpenPrice)
			await (await context.accountFacet.connect(context.signers.hedger2).allocateForPartyB(unDecimal(notional * decimal(12n, 17)), parentQuote.partyA)).wait()
			const {encryptedParams, upnlSig} = await hedger2.buildOpenPositionCalldataArgs(
				openRequest,
				context.partyBGroupActionsFacet.interface.getFunction("lockAndOpenQuote").selector,
			)
			const tx = await context.partyBGroupActionsFacet.connect(context.signers.hedger2).lockAndOpenQuote(
				quoteData.quoteId,
				encryptedParams,
				await getDummySingleUpnlSig(BigInt(openRequest.upnlPartyA)),
				upnlSig,
			)
			const receipt = await tx.wait()
			const partyAEvent = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "OpenPositionForPartyA")
			const partyBEvent = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "OpenPositionForPartyB")

			expect(partyAEvent).to.not.be.undefined
			expect(partyBEvent).to.not.be.undefined

			const partyAArgs = partyAEvent!.args as any[]
			const partyBArgs = partyBEvent!.args as any[]

			expect(partyAArgs[0]).to.equal(quoteData.quoteId)
			expect(partyAArgs[1]).to.equal(context.signers.user.address)
			expect(partyAArgs[2]).to.equal(context.signers.hedger2.address)
			expect(partyBArgs[0]).to.equal(quoteData.quoteId)
			expect(partyBArgs[1]).to.equal(context.signers.user.address)
			expect(partyBArgs[2]).to.equal(context.signers.hedger2.address)
			expect(await context.signers.user.decryptUint256(partyAArgs[3].filledAmount)).to.equal(filledAmount)
			expect(await context.signers.user.decryptUint256(partyAArgs[3].openedPrice)).to.equal(openedPrice)
			expect(await context.signers.hedger2.decryptUint256(partyBArgs[3].filledAmount)).to.equal(filledAmount)
			expect(await context.signers.hedger2.decryptUint256(partyBArgs[3].openedPrice)).to.equal(openedPrice)
			expect((await context.viewFacet.getQuote(3)).quoteStatus).to.be.eq(QuoteStatus.OPENED)
		})

		it("Should lock and open quote partially", async function () {
			const quoteData = quoteDataArray[3]
			const quantity = quoteData.partyBEvent ? await decryptUint256(context, quoteData.partyBEvent.values.quantity, context.signers.hedger2) : 0n
			const filledAmount = quantity / 2n
			await hedger2.lockAndOpenQuote(quoteData, decimal(12n, 17), limitOpenRequestBuilder()
				.filledAmount(filledAmount)
				.build())
			expect((await context.viewFacet.getQuote(3)).quoteStatus).to.be.eq(QuoteStatus.OPENED)
		})

		it("Should emit SendQuoteForPartyA values encrypted for PartyA on partial lockAndOpenQuote", async function () {
			const quoteData = quoteDataArray[3]
			const quantity = quoteData.partyBEvent
				? await decryptUint256(context, quoteData.partyBEvent.values.quantity, context.signers.hedger2)
				: 0n
			const filledAmount = quantity / 2n
			const parentQuote = await context.viewFacet.getQuote(quoteData.quoteId)
			const requestedOpenPrice = await decryptUint256(context, parentQuote.requestedOpenPrice.userCiphertext, context.signers.user)
			const notional = unDecimal(quantity * requestedOpenPrice)
			await (await context.accountFacet.connect(context.signers.hedger2).allocateForPartyB(unDecimal(notional * decimal(12n, 17)), parentQuote.partyA)).wait()

			// Disable trusted mode for the final tx so the event keying bug is observable in the test.
			await (await context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress)).wait()

			const openRequest = limitOpenRequestBuilder()
				.filledAmount(filledAmount)
				.build()
			const {encryptedParams, upnlSig} = await hedger2.buildOpenPositionCalldataArgs(
				openRequest,
				context.partyBGroupActionsFacet.interface.getFunction("lockAndOpenQuote").selector,
			)
			const tx = await context.partyBGroupActionsFacet.connect(context.signers.hedger2).lockAndOpenQuote(
				quoteData.quoteId,
				encryptedParams,
				await getDummySingleUpnlSig(BigInt(openRequest.upnlPartyA)),
				upnlSig,
			)
			const receipt = await tx.wait()
			const event = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "SendQuoteForPartyA")
			const partyBEvent = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "SendQuoteForPartyB")

			expect(event).to.not.be.undefined
			expect(partyBEvent).to.not.be.undefined

			const args = event!.args as any[]
			const partyBArgs = partyBEvent!.args as any[]
			const emittedValues = args[6]
			const partyADecryptedQuantity = await context.signers.user.decryptUint256(emittedValues.quantity)
			const partyADecryptedPrice = await context.signers.user.decryptUint256(emittedValues.price)
			const remainingQuantity = quantity - filledAmount

			expect(args[0]).to.equal(context.signers.user.address)
			expect(args[1]).to.equal(5n)
			expect(partyBArgs[0]).to.equal(context.signers.user.address)
			expect(partyBArgs[1]).to.equal(5n)
			expect(partyBArgs[2]).to.equal(context.signers.hedger2.address)
			expect(partyADecryptedQuantity).to.equal(remainingQuantity)
			expect(partyADecryptedPrice).to.equal(requestedOpenPrice)

			let partyBCouldDecryptCorrectly = false
			try {
				const partyBDecryptedQuantity = await context.signers.hedger2.decryptUint256(emittedValues.quantity)
				partyBCouldDecryptCorrectly = partyBDecryptedQuantity === remainingQuantity
			} catch {
				partyBCouldDecryptCorrectly = false
			}

			expect(partyBCouldDecryptCorrectly).to.equal(false)
		})
	})
}
