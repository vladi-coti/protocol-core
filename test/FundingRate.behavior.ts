import {loadFixtureCompatible, timeCompatible} from "./utils/testHelpers"

import {initializeFixture} from "./Initialize.fixture"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {decimal, decryptUint256, unDecimal} from "./utils/Common"
import {getDummyPairUpnlSig} from "./utils/SignatureUtils"
import {expect} from "chai"
import {limitQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {PositionType} from "./models/Enums"
import { QuoteData } from "./models/types";
import {runTx} from "./utils/TxUtils"

export function shouldBehaveLikeFundingRate(): void {
	let context: RunContext, user: User, user2: User, hedger: Hedger, hedger2: Hedger
	let quoteDataArray: {[key: string]: QuoteData} = {}

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)
		user = new User(context, context.signers.user)
		await user.setup()
		await user.setBalances(decimal(5000n), decimal(5000n), decimal(5000n))

		await runTx(context.controlFacet.connect(context.signers.admin).setSymbolFundingState(1, 120, 50))

		user2 = new User(context, context.signers.user2)

		hedger = new Hedger(context, context.signers.hedger)
		await hedger.setBalances(decimal(5000n), decimal(5000n))

		hedger2 = new Hedger(context, context.signers.hedger2)
		await hedger2.setBalances(decimal(5000n), decimal(5000n))

		quoteDataArray[1] = await user.sendQuote()
		await hedger.lockQuote(quoteDataArray[1])
		await hedger.openPosition(quoteDataArray[1])

		quoteDataArray[2] = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).positionType(PositionType.SHORT).build())
		await hedger.lockQuote(quoteDataArray[2])
		await hedger.openPosition(quoteDataArray[2])
		await user.requestToClosePosition(quoteDataArray[2].quoteId)

		quoteDataArray[3] = await user.sendQuote()
		await hedger.lockQuote(quoteDataArray[3])
		await hedger.openPosition(quoteDataArray[3])
		await user.requestToClosePosition(quoteDataArray[3].quoteId)
		await hedger.fillCloseRequest(quoteDataArray[3].quoteId)
	})

	it("Should fail on different length", async function () {
		await expect(hedger.chargeFundingRate(await context.signers.user.getAddress(), [1], [], await getDummyPairUpnlSig())).to.be.revertedWith(
			"ChargeFundingFacet: Length not match"
		)
	})

	it("Should fail on invalid quote for partyB", async function () {
		await expect(hedger.chargeFundingRate(await context.signers.user2.getAddress(), [1], [1], await getDummyPairUpnlSig())).to.be.revertedWith(
			"ChargeFundingFacet: Invalid quote"
		)
	})

	it("Should fail on invalid quote state", async function () {
		await expect(hedger.chargeFundingRate(await context.signers.user.getAddress(), [3], [1], await getDummyPairUpnlSig())).to.be.revertedWith(
			"ChargeFundingFacet: Invalid state"
		)
	})

	it("Should fail on out of window request", async function () {
		let symbol = await context.viewFacet.getSymbol(1)
		let duration = symbol.fundingRateEpochDuration
		let window = symbol.fundingRateWindowTime
		let currentEpoch = BigInt(await timeCompatible.latest()) / duration * duration
		let targetTime = (duration * 2n) + window + 1n + currentEpoch

		await timeCompatible.setNextBlockTimestamp(targetTime)
		await expect(hedger.chargeFundingRate(await context.signers.user.getAddress(), [1], [1], await getDummyPairUpnlSig())).to.be.revertedWith(
			"ChargeFundingFacet: Current timestamp is out of window"
		)
	})

	it("Should fail on high funding rate", async function () {
		let symbol = await context.viewFacet.getSymbol(1)
		let duration = symbol.fundingRateEpochDuration
		let window = symbol.fundingRateWindowTime
		let currentEpoch = BigInt(await timeCompatible.latest()) / duration * duration
		let targetTime = currentEpoch + duration + (window / 2n)

		await timeCompatible.setNextBlockTimestamp(targetTime)
		await expect(
			hedger.chargeFundingRate(await context.signers.user.getAddress(), [1], [decimal(3n, 16)], await getDummyPairUpnlSig())
		).to.be.revertedWith("ChargeFundingFacet: High funding rate")
	})

	it("Should fail on insolvent partyA", async function () {
		let symbol = await context.viewFacet.getSymbol(1)
		let duration = symbol.fundingRateEpochDuration
		let window = symbol.fundingRateWindowTime
		let currentEpoch = BigInt(await timeCompatible.latest()) / duration * duration
		let targetTime = currentEpoch + duration + (window / 2n)

		await timeCompatible.setNextBlockTimestamp(targetTime)
		await expect(
			hedger.chargeFundingRate(await context.signers.user.getAddress(), [1], [decimal(1n, 16)], await getDummyPairUpnlSig(decimal(4970n) * (-1n)))
		).to.be.revertedWith("ChargeFundingFacet: PartyA will be insolvent")
	})

	it("Should fail on insolvent partyB", async function () {
		let symbol = await context.viewFacet.getSymbol(1)
		let duration = symbol.fundingRateEpochDuration
		let window = symbol.fundingRateWindowTime
		let currentEpoch = BigInt(await timeCompatible.latest()) / duration * duration
		let targetTime = currentEpoch + duration + (window / 2n)

		await timeCompatible.setNextBlockTimestamp(targetTime)
		await expect(
			hedger.chargeFundingRate(
				await context.signers.user.getAddress(),
				[1],
				[decimal(1n, 15)],
				await getDummyPairUpnlSig(BigInt(0), decimal(4970n) * -1n)
			)
		).to.be.revertedWith("ChargeFundingFacet: PartyB will be insolvent")
	})

	it("Should run successfully for long", async function () {
		let symbol = await context.viewFacet.getSymbol(1)
		let duration = symbol.fundingRateEpochDuration
		let window = symbol.fundingRateWindowTime
		let currentEpoch = BigInt(await timeCompatible.latest()) / duration * duration
		let targetTime = currentEpoch + duration + (window / 2n)

		let oldQuote = await context.viewFacet.getQuote(1)
		let oldOpenedPrice = await decryptUint256(context, oldQuote.openedPrice, context.signers.user)

		await timeCompatible.setNextBlockTimestamp(targetTime)
		await hedger.chargeFundingRate(await context.signers.user.getAddress(), [1], [decimal(1n, 16)], await getDummyPairUpnlSig())

		let newQuote = await context.viewFacet.getQuote(1)
		let newOpenedPrice = await decryptUint256(context, newQuote.openedPrice, context.signers.user)
		expect(newOpenedPrice).to.be.equal(unDecimal(oldOpenedPrice * (decimal(1n) + decimal(1n, 16))))
	})

	it("Should run successfully for short", async function () {
		let symbol = await context.viewFacet.getSymbol(1)
		let duration = symbol.fundingRateEpochDuration
		let window = symbol.fundingRateWindowTime
		let currentEpoch = BigInt(await timeCompatible.latest()) / duration * duration
		let targetTime = currentEpoch + duration + (window / 2n)

		let oldQuote = await context.viewFacet.getQuote(2)
		let oldOpenedPrice = await decryptUint256(context, oldQuote.openedPrice, context.signers.user)

		await timeCompatible.setNextBlockTimestamp(targetTime)
		await hedger.chargeFundingRate(await context.signers.user.getAddress(), [2], [decimal(1n, 16)], await getDummyPairUpnlSig())

		let newQuote = await context.viewFacet.getQuote(2)
		let newOpenedPrice = await decryptUint256(context, newQuote.openedPrice, context.signers.user)
		expect(newOpenedPrice).to.be.equal(unDecimal(oldOpenedPrice * (decimal(1n) - decimal(1n, 16))))
	})
}
