import {loadFixtureCompatible, timeCompatible} from "./utils/testHelpers"

import {initializeFixture} from "./Initialize.fixture"
import {PositionType, QuoteStatus} from "./models/Enums"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {limitCloseRequestBuilder} from "./models/requestModels/CloseRequest"
import {limitQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {decimal, getBlockTimestamp, getQuoteQuantity} from "./utils/Common"
import {getDummyHighLowPriceSig, getDummySettlementSig} from "./utils/SignatureUtils"
import {ViewQuoteStructOutput} from "../src/types/contracts/interfaces/ISymmio"
import {limitOpenRequestBuilder} from "./models/requestModels/OpenRequest"
import {QuoteSettlementDataStructOutput} from "../src/types/contracts/facets/Settlement/ISettlementFacet"
import {expect} from "chai"
import {EventLog} from "ethers"
import {ethers} from "hardhat"
import {runTx} from "./utils/TxUtils"

export function shouldBehaveLikeSettleAndForceClosePosition(): void {
	let user: User, hedger: Hedger
	let context: RunContext
	let quote1LongOpened: ViewQuoteStructOutput, quote2ShortOpened: ViewQuoteStructOutput

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)
		this.user_allocated = decimal(500n)
		this.hedger_allocated = decimal(300n)

		user = new User(context, context.signers.user)
		await user.setup()
		await user.setBalances(decimal(2000n), decimal(1000n), this.user_allocated)

		hedger = new Hedger(context, context.signers.hedger)
		await hedger.setup()
		await hedger.setBalances(this.hedger_allocated, this.hedger_allocated)

		// Quote1 LONG opened
		const quote1LongOpenedData = await user.sendQuote()
		quote1LongOpened = await context.viewFacet.getQuote(quote1LongOpenedData.quoteId)
		await hedger.lockQuote(quote1LongOpenedData)
		await hedger.openPosition(quote1LongOpenedData)

		// Quote2 SHORT opened
		const quote2ShortOpenedData = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).positionType(PositionType.SHORT).quantity(decimal(75n)).build())
		quote2ShortOpened = await context.viewFacet.getQuote(quote2ShortOpenedData.quoteId)
		await hedger.lockQuote(quote2ShortOpenedData)
		await hedger.openPosition(quote2ShortOpenedData, limitOpenRequestBuilder().filledAmount(decimal(75n)).build())

		await user.requestToClosePosition(
			quote1LongOpened.id,
			limitCloseRequestBuilder()
				.quantityToClose(await getQuoteQuantity(context, quote1LongOpened.id))
				.closePrice(decimal(5n))
				.deadline((await getBlockTimestamp()) + 1000n)
				.build(),
		)
		await user.requestToClosePosition(
			quote2ShortOpened.id,
			limitCloseRequestBuilder()
				.quantityToClose(await getQuoteQuantity(context, quote2ShortOpened.id))
				.closePrice(decimal(5n))
				.deadline((await getBlockTimestamp()) + 1000n)
				.build(),
		)
		await runTx(context.controlFacet.setForceCloseMinSigPeriod(10))
		await runTx(context.controlFacet.setForceCloseGapRatio((await context.viewFacet.getQuote(quote1LongOpened.id)).symbolId, decimal(1n, 17)))

		quote1LongOpened = await context.viewFacet.getQuote(quote1LongOpened.id)
		quote2ShortOpened = await context.viewFacet.getQuote(quote2ShortOpened.id)
	})

	async function prepareSigTimes(period: bigint = 10n) {
		const now = await getBlockTimestamp()
		const cooldowns = await context.viewFacet.forceCloseCooldowns()
		const firstCooldown = cooldowns[0]
		const secondCooldown = cooldowns[1]
		const startTime = firstCooldown + now
		const endTime = firstCooldown + now + period
		await timeCompatible.increase(firstCooldown + period + secondCooldown + 1n)
		return [startTime, endTime]
	}

	it("Should settle and forceClose the quote", async function () {
		const sigTimes = await prepareSigTimes(100n)
		const highLowSig = await getDummyHighLowPriceSig(
			sigTimes[0],  // startTime
			sigTimes[1],  // endTime
			0n,           // lowest
			decimal(8n),  // highest
			decimal(6n),   // currentPrice
			decimal(5n),   // averagePrice
			quote1LongOpened.symbolId, // symbolId
			decimal(150n), // upnlPartyB
			0n             // upnlPartyA
		)
		const settlementSig = await getDummySettlementSig(0n, [150n], [
			{
				quoteId: quote2ShortOpened.id,
				currentPrice: decimal(7n),
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput,
		])
		await expect(
			user.settleAndForceClosePosition(quote1LongOpened.id, highLowSig, settlementSig, [])
		).to.be.revertedWith("LibQuote: Insufficient PnL balance")

		await runTx(context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress))
		const tx = await context.forceCloseFacet
			.connect(context.signers.user)
			.settleAndForceClosePosition(quote1LongOpened.id, highLowSig, settlementSig, [decimal(5n)])
		const receipt = await tx.wait()

		expect((await context.viewFacet.getQuote(quote1LongOpened.id)).quoteStatus).to.be.eq(QuoteStatus.CLOSED)
		expect(await context.signers.user.decryptUint256((await context.viewFacet.getQuote(quote2ShortOpened.id)).openedPrice)).to.be.eq(decimal(5n))

		const settlementEventsInterface = new ethers.Interface([
			"event SettleUpnl(tuple(uint256 quoteId,uint256 currentPrice)[] settlementData,address partyA,tuple(uint256 ciphertextHigh,uint256 ciphertextLow) newPartyAAllocatedBalance,tuple(uint256 ciphertextHigh,uint256 ciphertextLow)[] newPartyBsAllocatedBalances)",
		])
		const event = receipt!.logs
			.map((log: any) => {
				try {
					return settlementEventsInterface.parseLog(log)
				} catch {
					return null
				}
			})
			.find((log: any): log is EventLog => log?.name === "SettleUpnl")
		expect(event).to.not.be.undefined

		const emittedBalanceTuple = event!.args.newPartyBsAllocatedBalances[0] as [bigint, bigint]
		expect(emittedBalanceTuple).to.have.length(2)

		const storedBalance = await context.viewFacet.allocatedBalanceOfPartyB(await hedger.getAddress(), await user.getAddress())
		expect(emittedBalanceTuple[0]).to.equal(storedBalance.ciphertextHigh)
		expect(emittedBalanceTuple[1]).to.equal(storedBalance.ciphertextLow)

		const emittedBalance = {
			ciphertextHigh: emittedBalanceTuple[0],
			ciphertextLow: emittedBalanceTuple[1],
		}

		const decryptedByPartyB = await context.signers.hedger.decryptUint256(emittedBalance)
		const decryptedStoredBalance = await context.signers.hedger.decryptUint256(storedBalance)
		expect(decryptedByPartyB).to.equal(decryptedStoredBalance)
	})
}
