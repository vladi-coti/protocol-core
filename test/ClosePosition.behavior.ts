import {loadFixtureCompatible, timeCompatible} from "./utils/testHelpers"
import {expect} from "chai"
import {ethers} from "hardhat"

import {initializeFixture} from "./Initialize.fixture"
import {OrderType, PositionType, QuoteStatus} from "./models/Enums"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {limitCloseRequestBuilder, marketCloseRequestBuilder} from "./models/requestModels/CloseRequest"
import {limitQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {
	decimal,
	decryptUint256,
	getBlockTimestamp,
	getQuoteMinLeftQuantityForClose,
	getQuoteQuantity,
	getTotalLockedValuesForQuoteIds,
	getTradingFeeForQuotes,
	pausePartyA,
	pausePartyB,
	unDecimal,
} from "./utils/Common"
import {CloseRequestValidator} from "./models/validators/CloseRequestValidator"
import {FillCloseRequest, limitFillCloseRequestBuilder, marketFillCloseRequestBuilder} from "./models/requestModels/FillCloseRequest"
import {FillCloseRequestValidator} from "./models/validators/FillCloseRequestValidator"
import {CancelCloseRequestValidator} from "./models/validators/CancelCloseRequestValidator"
import {AcceptCancelCloseRequestValidator} from "./models/validators/AcceptCancelCloseRequestValidator"
import {QuoteData} from "./models/types";

export function shouldBehaveLikeClosePosition(): void {
	let user: User, hedger: Hedger, hedger2: Hedger
	let context: RunContext
	let quoteDataArray: {[key: string]: QuoteData} = {}
	const realizedPnlIn = 4n
	const realizedPnlOut = 5n
	const sharedEventsInterface = new ethers.Interface([
		"event BalanceChangePartyA(address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
		"event BalanceChangePartyB(address indexed partyB, address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
	])

	async function fillCloseAndGetReceipt(quoteId: bigint, request: FillCloseRequest) {
		const {encryptedParams, upnlSig} = await hedger.buildFillCloseRequestCalldataArgs(request)
		const tx = await context.partyBPositionActionsFacet.connect(context.signers.hedger).fillCloseRequest(quoteId, encryptedParams, upnlSig)
		const receipt = await tx.wait()
		if (!receipt) throw new Error("FillCloseRequest failed")
		return receipt
	}

	function getPnlEventLogs(receipt: any): any[] {
		return receipt.logs
			.map((log: any) => {
				try {
					return sharedEventsInterface.parseLog(log)
				} catch {
					return null
				}
			})
			.filter((log: any) => {
				if (!log || (log.name !== "BalanceChangePartyA" && log.name !== "BalanceChangePartyB")) return false
				const eventType = getBalanceChangeType(log)
				return eventType === realizedPnlIn || eventType === realizedPnlOut
			})
	}

	function getBalanceChangeAmount(log: any) {
		return log.args.amount
	}

	function getBalanceChangeType(log: any): bigint {
		return BigInt(log.args._type)
	}

	function pnlEventShape(receipt: any): string[] {
		return getPnlEventLogs(receipt).map(log => `${log.name}:${getBalanceChangeType(log).toString()}`)
	}

	async function pnlEventAmounts(receipt: any) {
		const logs = getPnlEventLogs(receipt)
		const amounts = {
			partyAIn: 0n,
			partyAOut: 0n,
			partyBIn: 0n,
			partyBOut: 0n,
		}

		for (const log of logs) {
			const amount = await decryptUint256(context, getBalanceChangeAmount(log), context.signers.user)
			const eventType = getBalanceChangeType(log)
			if (log.name === "BalanceChangePartyA" && eventType === realizedPnlIn) amounts.partyAIn = amount
			if (log.name === "BalanceChangePartyA" && eventType === realizedPnlOut) amounts.partyAOut = amount
			if (log.name === "BalanceChangePartyB" && eventType === realizedPnlIn) amounts.partyBIn = amount
			if (log.name === "BalanceChangePartyB" && eventType === realizedPnlOut) amounts.partyBOut = amount
		}

		return amounts
	}

	async function quotePnl(quoteId: bigint, closedPrice: bigint): Promise<bigint> {
		const quote = await context.viewFacet.getQuote(quoteId)
		const openedPrice = await decryptUint256(context, quote.openedPrice.userCiphertext, context.signers.user)
		const quantity = await getQuoteQuantity(context, quoteId)
		const priceDiff = closedPrice > openedPrice ? closedPrice - openedPrice : openedPrice - closedPrice
		return unDecimal(quantity * priceDiff)
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

		// Quote1 LONG opened
		quoteDataArray[1] = await user.sendQuote()
		await hedger.lockQuote(quoteDataArray[1])
		await hedger.openPosition(quoteDataArray[1])

		// Quote2 SHORT opened
		quoteDataArray[2] = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).positionType(PositionType.SHORT).build())
		await hedger.lockQuote(quoteDataArray[2])
		await hedger.openPosition(quoteDataArray[2])

		// Quote3 SHORT sent
		quoteDataArray[3] = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).positionType(PositionType.SHORT).build())

		// Quote4 LONG sent
		quoteDataArray[4] = await user.sendQuote()
		await hedger.lockQuote(quoteDataArray[4])
		await hedger.openPosition(quoteDataArray[4])
	})

	it("Should fail on invalid partyA", async function () {
		const contractAddress = context.diamond
		const selector = context.partyAFacet.interface.getFunction("requestToClosePosition").selector

		const encryptedClosePrice = await user.encryptUint256(BigInt(1n), contractAddress, selector);
		const encryptedQuantityToClose = await user.encryptUint256(BigInt(1n), contractAddress, selector);

		await expect(
			context.partyAFacet.requestToClosePosition(
				2n, //quoteId
				encryptedClosePrice,
				encryptedQuantityToClose,
				BigInt(OrderType.LIMIT),
				await getBlockTimestamp(100n),
			),
		).to.be.revertedWith("Accessibility: Should be partyA of quote")
	})

	it("Should fail on paused partyA", async function () {
		await pausePartyA(context)
		await expect(user.requestToClosePosition(2)).to.be.revertedWith("Pausable: PartyA actions paused")
	})

	it("Should fail on invalid quoteId", async function () {
		await expect(user.requestToClosePosition(50)).to.be.reverted
	})

	it("Should fail on invalid quote state", async function () {
		await expect(user.requestToClosePosition(3)).to.be.revertedWith("PartyAFacet: Invalid state")
	})

	it("Should fail on invalid quantityToClose", async function () {
		const quantity = await getQuoteQuantity(context, 1n)
		await expect(
			user.requestToClosePosition(
				1,
				limitCloseRequestBuilder()
					.quantityToClose(quantity + decimal(1n))
					.build(),
			),
		).to.be.revertedWith("PartyAFacet: Invalid quantityToClose")
		await expect(
			user.requestToClosePosition(
				1,
				limitCloseRequestBuilder()
					.quantityToClose(quantity + decimal(1n))
					.build(),
			),
		).to.be.revertedWith("PartyAFacet: Invalid quantityToClose")
	})

	it("ClosePosition - Should request limit successfully", async function () {
		const validator = new CloseRequestValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
		})
		const closePrice = decimal(1n, 17)
		const quantityToClose = await getQuoteQuantity(context, 1n)
		await user.requestToClosePosition(1, limitCloseRequestBuilder().quantityToClose(quantityToClose).closePrice(closePrice).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
			closePrice: closePrice,
			quantityToClose: quantityToClose,
			beforeOutput: beforeOut,
		})
	})

	it("ClosePosition - Should request limit successfully partially", async function () {
		const quantity = await getQuoteQuantity(context, 1n)
		const validator = new CloseRequestValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
		})
		const closePrice = decimal(1n, 17)
		const quantityToClose = quantity / 2n
		await user.requestToClosePosition(1, limitCloseRequestBuilder().quantityToClose(quantityToClose).closePrice(closePrice).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
			closePrice: closePrice,
			quantityToClose: quantityToClose,
			beforeOutput: beforeOut,
		})
	})

	it("ClosePosition - Should reject partial request that leaves quote value below minimum", async function () {
		const quantity = await getQuoteQuantity(context, 1n)
		const minLeftQuantity = await getQuoteMinLeftQuantityForClose(context, 1n)
		await expect(
			user.requestToClosePosition(
				1,
				limitCloseRequestBuilder()
					.quantityToClose(quantity - minLeftQuantity + 1n)
					.closePrice(decimal(1n, 17))
					.build(),
			),
		).to.be.revertedWith("PartyAFacet: Remaining quote value is low")
	})

	it("ClosePosition - Should request market successfully", async function () {
		const validator = new CloseRequestValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
		})
		const closePrice = decimal(1n, 17)
		const quantityToClose = await getQuoteQuantity(context, 1n)
		await user.requestToClosePosition(1, marketCloseRequestBuilder().quantityToClose(quantityToClose).closePrice(closePrice).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
			closePrice: closePrice,
			quantityToClose: quantityToClose,
			beforeOutput: beforeOut,
		})
	})

	it("ClosePosition - Should request market successfully partially", async function () {
		const quantity = await getQuoteQuantity(context, 1n)
		const validator = new CloseRequestValidator()
		const beforeOut = await validator.before(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
		})
		const closePrice = decimal(1n, 17)
		const quantityToClose = quantity / 2n
		await user.requestToClosePosition(1, marketCloseRequestBuilder().quantityToClose(quantityToClose).closePrice(closePrice).build())
		await validator.after(context, {
			user: user,
			hedger: hedger,
			quoteId: BigInt(1),
			closePrice: closePrice,
			quantityToClose: quantityToClose,
			beforeOutput: beforeOut,
		})
	})

	it("ClosePosition - Should keep PnL event shape constant for profit and loss", async function () {
		const partyA = await user.getAddress()
		const profitQuantity = await getQuoteQuantity(context, 1n)
		const profitClosePrice = decimal(11n, 17)
		const profitPnl = await quotePnl(1n, profitClosePrice)
		const userBeforeProfit = await user.getBalanceInfo()
		const hedgerBeforeProfit = await hedger.getBalanceInfo(partyA)

		await user.requestToClosePosition(
			1,
			limitCloseRequestBuilder()
				.quantityToClose(profitQuantity)
				.closePrice(decimal(1n))
				.build(),
		)
		const profitReceipt = await fillCloseAndGetReceipt(
			1n,
			limitFillCloseRequestBuilder()
				.filledAmount(profitQuantity)
				.closedPrice(profitClosePrice)
				.build(),
		)

		const userAfterProfit = await user.getBalanceInfo()
		const hedgerAfterProfit = await hedger.getBalanceInfo(partyA)
		expect(userAfterProfit.allocatedBalances - userBeforeProfit.allocatedBalances).to.equal(profitPnl)
		expect(hedgerBeforeProfit.allocatedBalances - hedgerAfterProfit.allocatedBalances).to.equal(profitPnl)

		const lossQuantity = await getQuoteQuantity(context, 4n)
		const lossClosePrice = decimal(9n, 17)
		const lossPnl = await quotePnl(4n, lossClosePrice)
		const userBeforeLoss = await user.getBalanceInfo()
		const hedgerBeforeLoss = await hedger.getBalanceInfo(partyA)

		await user.requestToClosePosition(
			4,
			limitCloseRequestBuilder()
				.quantityToClose(lossQuantity)
				.closePrice(decimal(8n, 17))
				.build(),
		)
		const lossReceipt = await fillCloseAndGetReceipt(
			4n,
			limitFillCloseRequestBuilder()
				.filledAmount(lossQuantity)
				.closedPrice(lossClosePrice)
				.build(),
		)

		const userAfterLoss = await user.getBalanceInfo()
		const hedgerAfterLoss = await hedger.getBalanceInfo(partyA)
		expect(userBeforeLoss.allocatedBalances - userAfterLoss.allocatedBalances).to.equal(lossPnl)
		expect(hedgerAfterLoss.allocatedBalances - hedgerBeforeLoss.allocatedBalances).to.equal(lossPnl)

		expect(pnlEventShape(profitReceipt)).to.deep.equal(pnlEventShape(lossReceipt))
		expect(pnlEventShape(profitReceipt)).to.deep.equal([
			"BalanceChangePartyA:4",
			"BalanceChangePartyA:5",
			"BalanceChangePartyB:4",
			"BalanceChangePartyB:5",
		])

		const profitAmounts = await pnlEventAmounts(profitReceipt)
		expect(profitAmounts.partyAIn).to.equal(profitPnl)
		expect(profitAmounts.partyAOut).to.equal(0n)
		expect(profitAmounts.partyBIn).to.equal(0n)
		expect(profitAmounts.partyBOut).to.equal(profitPnl)

		const lossAmounts = await pnlEventAmounts(lossReceipt)
		expect(lossAmounts.partyAIn).to.equal(0n)
		expect(lossAmounts.partyAOut).to.equal(lossPnl)
		expect(lossAmounts.partyBIn).to.equal(lossPnl)
		expect(lossAmounts.partyBOut).to.equal(0n)
	})

	it("ClosePosition - Should expire close request", async function () {
		await user.requestToClosePosition(
			1,
			limitCloseRequestBuilder()
				.quantityToClose(await getQuoteQuantity(context, 1n))
				.closePrice(decimal(1n, 17))
				.build(),
		)
		await timeCompatible.increase(1000)
		await context.partyAFacet.expireQuote([1])
		let q = await context.viewFacet.getQuote(1)
		expect(q.quoteStatus).to.be.equal(QuoteStatus.OPENED)
	})

	describe("Fill Close Request", async function () {
		beforeEach(async function () {
			await user.requestToClosePosition(
				1,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, 1n))
					.closePrice(decimal(1n))
					.build(),
			)
			await user.requestToClosePosition(
				2,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, 2n))
					.closePrice(decimal(1n))
					.build(),
			)
			await user.requestToClosePosition(
				4,
				marketCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, 4n))
					.closePrice(decimal(1n))
					.build(),
			)
		})

		it("Fill Close Request - Should fail on invalid partyB", async function () {
			await expect(
				hedger2.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(decimal(1n))
						.build(),
				),
			).to.be.revertedWith("Accessibility: Should be partyB of quote")
		})

		it("Fill Close Request - Should fail on paused partyB", async function () {
			await pausePartyB(context)
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(decimal(1n))
						.build(),
				),
			).to.be.revertedWith("Pausable: PartyB actions paused")
		})

		it("Fill Close Request - Should fail on fill amount", async function () {
			const quantity = await getQuoteQuantity(context, 1n)
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(quantity + decimal(1n))
						.build(),
				),
			).to.be.revertedWith("PartyBFacet: Invalid filledAmount")
			await expect(
				hedger.fillCloseRequest(
					4,
					limitFillCloseRequestBuilder()
						.filledAmount(quantity + decimal(1n))
						.build(),
				),
			).to.be.revertedWith("PartyBFacet: Invalid filledAmount")
		})

		it("Fill Close Request - Should fail on invalid close price", async function () {
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(decimal(1n, 17))
						.build(),
				),
			).to.be.revertedWith("PBF:price")

			await expect(
				hedger.fillCloseRequest(
					2,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 2n))
						.closedPrice(decimal(2n))
						.build(),
				),
			).to.be.revertedWith("PBF:price")
		})

		it("Fill Close Request - Should fail on negative balance of partyA/partyB", async function () {
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(decimal(1n))
						.upnlPartyA(decimal(-575n))
						.build(),
				),
			).to.be.revertedWith("LibSolvency: Available partyA balance is lower than zero")
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(decimal(1n))
						.upnlPartyB(decimal(-410n))
						.build(),
				),
			).to.be.revertedWith("LibSolvency: Available partyB balance is lower than zero")
		})

		it("Fill Close Request - Should fail on partyB becoming liquidatable", async function () {
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(decimal(1n))
						.upnlPartyB(decimal(-300n))
						.price(decimal(1n, 17))
						.build(),
				),
			).to.be.revertedWith("LibSolvency: Available partyB balance is lower than zero")
			await expect(
				hedger.fillCloseRequest(
					2,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 2n))
						.closedPrice(decimal(1n, 17))
						.upnlPartyB(decimal(-300n))
						.build(),
				),
			).to.be.revertedWith("LibSolvency: Available partyB balance is lower than zero")
		})

		it("Fill Close Request - Should fail on partyA becoming liquidatable", async function () {
			let quantity = await getQuoteQuantity(context, 1n)
			let price = decimal(11n, 17)
			let closePrice = decimal(1n)
			let userAvailable = this.user_allocated
				- (await getTotalLockedValuesForQuoteIds(context, [2n, 4n], context.signers.user, false))
				- (await getTradingFeeForQuotes(context, [1n, 2n, 3n, 4n]))
				- (unDecimal(quantity * (price - closePrice)))

			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(quantity)
						.closedPrice(closePrice)
						.upnlPartyA((userAvailable + (decimal(1n))) * (-1n))
						.price(price)
						.build(),
				),
			).to.be.revertedWith("LibSolvency: Available partyA balance is lower than zero")

			quantity = await getQuoteQuantity(context, 1n)
			price = decimal(1n, 17)
			closePrice = decimal(1n)
			userAvailable = this.user_allocated
				- (await getTotalLockedValuesForQuoteIds(context, [1n, 4n], context.signers.user, false))
				- (await getTradingFeeForQuotes(context, [1n, 2n, 3n, 4n]))
				- (unDecimal(quantity * (closePrice - price)))

			await expect(
				hedger.fillCloseRequest(
					2,
					limitFillCloseRequestBuilder()
						.filledAmount(quantity)
						.closedPrice(closePrice)
						.upnlPartyA((userAvailable + (decimal(1n))) * (-1n))
						.price(price)
						.build(),
				),
			).to.be.revertedWith("LibSolvency: Available partyA balance is lower than zero")
		})

		it("Fill Close Request - Should fail due to expired request", async function () {
			await timeCompatible.increase(1000)
			let closePrice = decimal(11n, 17)
			await expect(
				hedger.fillCloseRequest(
					1,
					limitFillCloseRequestBuilder()
						.filledAmount(await getQuoteQuantity(context, 1n))
						.closedPrice(closePrice)
						.build(),
				),
			).to.be.revertedWith("PartyBFacet: Quote is expired")
		})

		it("Fill Close Request - Should run successfully for limit", async function () {
			const validator = new FillCloseRequestValidator()
			const beforeOut = await validator.before(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
			})
			let closePrice = decimal(11n, 17)
			const filledAmount = await getQuoteQuantity(context, 1n)
			await hedger.fillCloseRequest(1, limitFillCloseRequestBuilder().filledAmount(filledAmount).closedPrice(closePrice).build())
			await validator.after(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
				closePrice: closePrice,
				fillAmount: filledAmount,
				beforeOutput: beforeOut,
			})
		})

		it("Fill Close Request - Should run successfully partially for limit", async function () {
			const closePrice = decimal(11n, 17)
			const quantity = await getQuoteQuantity(context, 1n)
			const filledAmount = quantity / 2n
			const validator = new FillCloseRequestValidator()
			const beforeOut = await validator.before(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
			})
			await hedger.fillCloseRequest(1, limitFillCloseRequestBuilder().filledAmount(filledAmount).closedPrice(closePrice).build())
			await validator.after(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
				closePrice: closePrice,
				fillAmount: filledAmount,
				beforeOutput: beforeOut,
			})
		})

		it("Fill Close Request - Should run successfully for market", async function () {
			let closePrice = decimal(11n, 17)
			const validator = new FillCloseRequestValidator()
			const beforeOut = await validator.before(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(4),
			})
			const filledAmount = await getQuoteQuantity(context, 4n)
			await hedger.fillCloseRequest(4, marketFillCloseRequestBuilder().filledAmount(filledAmount).closedPrice(closePrice).build())
			await validator.after(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(4),
				closePrice: closePrice,
				fillAmount: filledAmount,
				beforeOutput: beforeOut,
			})
		})
	})

	describe("Cancel Close Request", async function () {
		beforeEach(async function () {
			await user.requestToClosePosition(
				1,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, 4n))
					.build(),
			)
		})

		it("Should fail on invalid quoteId", async function () {
			await expect(user.requestToCancelCloseRequest(3)).to.be.reverted
		})

		it("Should fail on invalid partyA", async function () {
			await expect(context.partyAFacet.connect(context.signers.user2).requestToCancelCloseRequest(1)).to.be.revertedWith(
				"Accessibility: Should be partyA of quote",
			)
		})

		it("Should fail on paused partyA", async function () {
			await pausePartyA(context)
			await expect(user.requestToCancelCloseRequest(1)).to.be.revertedWith("Pausable: PartyA actions paused")
		})

		it("Should fail on invalid state", async function () {
			await expect(user.requestToCancelCloseRequest(2)).to.be.revertedWith("PartyAFacet: Invalid state")
		})

		it("Should send cancel request successfully", async function () {
			const validator = new CancelCloseRequestValidator()
			const beforeOut = await validator.before(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
			})
			await user.requestToCancelCloseRequest(1)
			await validator.after(context, {
				user: user,
				hedger: hedger,
				quoteId: BigInt(1),
				beforeOutput: beforeOut,
			})
		})

		it("Should expire request", async function () {
			await timeCompatible.increase(1000)
			await user.requestToCancelCloseRequest(1)
			expect((await context.viewFacet.getQuote(1)).quoteStatus).to.be.equal(QuoteStatus.OPENED)
		})

		describe("Accepting cancel request", async function () {
			this.beforeEach(async function () {
				await user.requestToCancelCloseRequest(1)
			})

			it("Should fail on invalid quoteId", async function () {
				await expect(hedger.acceptCancelCloseRequest(3)).to.be.reverted
			})

			it("Should fail on invalid partyB", async function () {
				await expect(hedger2.acceptCancelCloseRequest(1)).to.be.revertedWith("Accessibility: Should be partyB of quote")
			})

			it("Should fail on paused partyB", async function () {
				await pausePartyB(context)
				await expect(hedger.acceptCancelCloseRequest(1)).to.be.revertedWith("Pausable: PartyB actions paused")
			})

			it("Should fail on invalid state", async function () {
				await expect(hedger.acceptCancelCloseRequest(2)).to.be.revertedWith("PartyBFacet: Invalid state")
			})

			it("Should run successfully", async function () {
				const validator = new AcceptCancelCloseRequestValidator()
				const beforeOut = await validator.before(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
				})
				await hedger.acceptCancelCloseRequest(1)
				await validator.after(context, {
					user: user,
					hedger: hedger,
					quoteId: BigInt(1),
					beforeOutput: beforeOut,
				})
			})

			it("Should force cancel close request", async function () {
				await expect(user.forceCancelCloseRequest(2)).to.be.revertedWith("PartyAFacet: Invalid state")
				await expect(user.forceCancelCloseRequest(1)).to.be.revertedWith("PartyAFacet: Cooldown not reached")
				await timeCompatible.increase(300)
				await user.forceCancelCloseRequest(1)
				expect((await context.viewFacet.getQuote(1)).quoteStatus).to.be.eq(QuoteStatus.OPENED)
			})
		})
	})
}
