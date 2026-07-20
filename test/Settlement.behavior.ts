import {loadFixtureCompatible} from "./utils/testHelpers"

import {initializeFixture} from "./Initialize.fixture"
import {PositionType} from "./models/Enums"
import {Hedger} from "./models/Hedger"
import {RunContext} from "./models/RunContext"
import {User} from "./models/User"
import {limitQuoteRequestBuilder} from "./models/requestModels/QuoteRequest"
import {decimal, decryptUint256, unDecimal} from "./utils/Common"
import {expect} from "chai"
import {getDummySettlementSig, getDummySingleUpnlSig} from "./utils/SignatureUtils"
import {QuoteSettlementDataStructOutput} from "../src/types/contracts/facets/Settlement/ISettlementFacet"
import {QuoteData} from "./models/types"
import {EventLog} from "ethers"
import {ethers} from "hardhat"

export function shouldBehaveLikeSettlement(): void {
	let context: RunContext, user: User, user2: User, hedger: Hedger, hedger2: Hedger
	let longHedger1: QuoteData, shortHedger1: QuoteData, shortHedger2: QuoteData, shortClosePending: QuoteData,
		longClosed: QuoteData, longHedger1User2: QuoteData

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)
		this.user_allocated = decimal(700n)
		this.hedger_allocated = decimal(4000n)

		user = new User(context, context.signers.user)
		await user.setup()
		await user.setBalances(decimal(2000n), decimal(1000n), this.user_allocated)

		user2 = new User(context, context.signers.user2)
		await user2.setup()
		await user2.setBalances(decimal(2000n), decimal(1000n), this.user_allocated)

		hedger = new Hedger(context, context.signers.hedger)
		await hedger.setup()
		await hedger.setBalances(this.hedger_allocated, this.hedger_allocated)

		hedger2 = new Hedger(context, context.signers.hedger2)
		await hedger2.setup()
		await hedger2.setBalances(this.hedger_allocated, this.hedger_allocated)

		longHedger1 = await user.sendQuote()
		await hedger.lockQuote(longHedger1)
		await hedger.openPosition(longHedger1)

		longHedger1User2 = await user2.sendQuote()
		await hedger.lockQuote(longHedger1User2)
		await hedger.openPosition(longHedger1User2)

		shortHedger1 = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).positionType(PositionType.SHORT).build())
		await hedger.lockQuote(shortHedger1)
		await hedger.openPosition(shortHedger1)

		shortHedger2 = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger2.address]).positionType(PositionType.SHORT).build())
		await hedger2.lockQuote(shortHedger2)
		await hedger2.openPosition(shortHedger2)

		shortClosePending = await user.sendQuote(limitQuoteRequestBuilder().partyBWhiteList([context.signers.hedger.address]).positionType(PositionType.SHORT).build())
		await hedger.lockQuote(shortClosePending)
		await hedger.openPosition(shortClosePending)
		await user.requestToClosePosition(shortClosePending.quoteId)

		longClosed = await user.sendQuote()
		await hedger.lockQuote(longClosed)
		await hedger.openPosition(longClosed)
		await user.requestToClosePosition(longClosed.quoteId)
		await hedger.fillCloseRequest(longClosed.quoteId)
	})

	it("Should fail when partyB actions paused", async function () {
		await context.controlFacet.connect(context.signers.admin).pausePartyBActions()
		await expect(hedger.settleUpnl(await user.getAddress(), [])).to.be.revertedWith("Pausable: PartyB actions paused")
	})

	it("Should fail when partyA is liquidated", async function () {
		await user.liquidateAndSetSymbolPrices([1n], [decimal(10000000n)])
		await expect(hedger.settleUpnl(await user.getAddress(), [])).to.be.revertedWith("Accessibility: PartyA isn't solvent")
	})

	it("Should fail when settlementData.length != updatedPrices.length", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [1n])).to.be.revertedWith("LibSettlement: Invalid length")
	})

	it("Should fail when when partyA is insolvent", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [1n], getDummySettlementSig(decimal(600n) * -1n, [0n], [
			{
				quoteId: longHedger1User2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: PartyA is insolvent")
	})

	it("Should fail if sender doesn't have open position with user", async function () {
		await expect(hedger2.settleUpnl(await user2.getAddress(), [1n], getDummySettlementSig(decimal(600n) * -1n, [0n], [
			{
				quoteId: longHedger1User2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: Sender should have a position with partyA")
	})

	it("Should fail if one of quotes has different partyA than the one in parameter", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [1n], getDummySettlementSig(0n, [0n], [
			{
				quoteId: longHedger1User2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: PartyA is invalid")
	})

	it("Should fail if the quoteStatus is neither OPENED/CLOSE_PENDING/CANCEL_CLOSE_PENDING", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [1n], getDummySettlementSig(0n, [0n], [
			{
				quoteId: longClosed.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: Invalid state")
	})

	it("Should fail if the newPrice hasn't move to the right direction (Both for short and long)", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [decimal(0n)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: longHedger1.quoteId,
				currentPrice: decimal(2n),
				partyBUpnlIndex: decimal(0n)
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: Updated price is out of range")
		await expect(hedger.settleUpnl(await user.getAddress(), [decimal(2n)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: decimal(0n),
				partyBUpnlIndex: decimal(0n)
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: Updated price is out of range")
	})

	it("Should fail if partyB is in liquidation process", async function () {
		await hedger.liquidate(await user.getAddress(), await getDummySingleUpnlSig(decimal(10000n) * -1n) as any)
		await expect(hedger.settleUpnl(await user.getAddress(), [1n], getDummySettlementSig(0n, [0n], [
			{
				quoteId: longHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: PartyB is in liquidation process")
	})

	it("Should fail if partyB is not solvent", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [1n], getDummySettlementSig(0n, [decimal(10000n) * -1n], [
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: PartyB should be solvent")
	})

	it("Should revert instead of wrapping when settlement exceeds partyB balance", async function () {
		const partyA = await user.getAddress()
		const sig = await getDummySettlementSig(0n, [decimal(100000n)], [
			{
				quoteId: longHedger1.quoteId,
				currentPrice: decimal(100n),
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		])
		let reverted = false
		try {
			const tx = await context.settlementFacet.connect(context.signers.hedger).settleUpnl(sig, [decimal(50n)], partyA)
			await tx.wait()
		} catch {
			reverted = true
		}
		expect(reverted).to.equal(true)
	})

	it("Should fail if partyB is settling too frequently for the relation of user with another partyB", async function () {
		await hedger.settleUpnl(await user.getAddress(), [decimal(5n, 17)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))
		await expect(hedger.settleUpnl(await user.getAddress(), [decimal(2n, 17)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: Cooldown should be passed")
	})

	it("Should fail on invalid partyBUpnlIndex in signature", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [decimal(5n, 17)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 3n
			} as QuoteSettlementDataStructOutput,
		]))).to.be.revertedWith("LibSettlement: Invalid partyBUpnlIndex in signature")
	})


	it("Should fail on invalid upnlPartyBs list", async function () {
		await expect(hedger.settleUpnl(await user.getAddress(), [decimal(5n, 17), decimal(5n, 17)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput,
			{
				quoteId: shortHedger2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))).to.be.revertedWith("LibSettlement: Invalid upnlPartyBs list")
	})

	it("Should run successfully", async function () {
		const beforeNoncePartyA = await context.viewFacet.nonceOfPartyA(await user.getAddress())
		const beforeNoncePartyB = await context.viewFacet.nonceOfPartyB(await hedger.getAddress(), await user.getAddress())
		const beforeNoncePartyB2 = await context.viewFacet.nonceOfPartyB(await hedger2.getAddress(), await user.getAddress())

		const beforeAllocatedPartyA = (await user.getBalanceInfo()).allocatedBalances
		const beforeAllocatedPartyB = (await hedger.getBalanceInfo(await user.getAddress())).allocatedBalances
		const beforeAllocatedPartyB2 = (await hedger2.getBalanceInfo(await user.getAddress())).allocatedBalances

		const longQuote = await context.viewFacet.getQuote(longHedger1.quoteId)
		const shortQuote1 = await context.viewFacet.getQuote(shortHedger1.quoteId)
		const shortQuote2 = await context.viewFacet.getQuote(shortHedger2.quoteId)

		await hedger.settleUpnl(await user.getAddress(), [decimal(15n, 17), decimal(5n, 17), decimal(5n, 17)], getDummySettlementSig(0n, [0n, 0n], [
			{
				quoteId: longHedger1.quoteId,
				currentPrice: decimal(2n),
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput,
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput,
			{
				quoteId: shortHedger2.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 1n
			} as QuoteSettlementDataStructOutput
		]))
		expect(await context.viewFacet.nonceOfPartyA(await user.getAddress())).to.be.eq(beforeNoncePartyA + 1n)
		expect(await context.viewFacet.nonceOfPartyB(await hedger.getAddress(), await user.getAddress())).to.be.eq(beforeNoncePartyB + 1n)
		expect(await context.viewFacet.nonceOfPartyB(await hedger2.getAddress(), await user.getAddress())).to.be.eq(beforeNoncePartyB2 + 1n)

		const updatedLongQuote = await context.viewFacet.getQuote(longHedger1.quoteId)
		const updatedShortQuote1 = await context.viewFacet.getQuote(shortHedger1.quoteId)
		const updatedShortQuote2 = await context.viewFacet.getQuote(shortHedger2.quoteId)
		const openedPriceLong = await decryptUint256(context, updatedLongQuote.openedPrice, context.signers.user)
		const openedPriceShort1 = await decryptUint256(context, updatedShortQuote1.openedPrice, context.signers.user)
		const openedPriceShort2 = await decryptUint256(context, updatedShortQuote2.openedPrice, context.signers.user)
		expect(openedPriceLong).to.be.eq(decimal(15n, 17))
		expect(openedPriceShort1).to.be.eq(decimal(5n, 17))
		expect(openedPriceShort2).to.be.eq(decimal(5n, 17))

		const decryptedLongQuantity = await decryptUint256(context, longQuote.quantity, context.signers.user)
		const decryptedShortQuantity1 = await decryptUint256(context, shortQuote1.quantity, context.signers.user)
		const decryptedShortQuantity2 = await decryptUint256(context, shortQuote2.quantity, context.signers.user)
		
		expect((await user.getBalanceInfo()).allocatedBalances).to.be.eq(beforeAllocatedPartyA + unDecimal((decryptedLongQuantity + decryptedShortQuantity1 + decryptedShortQuantity2) * decimal(5n, 17)))
		expect((await hedger.getBalanceInfo(await user.getAddress())).allocatedBalances).to.be.eq(beforeAllocatedPartyB - unDecimal((decryptedLongQuantity + decryptedShortQuantity1) * decimal(5n, 17)))
		expect((await hedger2.getBalanceInfo(await user.getAddress())).allocatedBalances).to.be.eq(beforeAllocatedPartyB2 - unDecimal(decryptedShortQuantity2 * decimal(5n, 17)))
	})

	it("Should settle long and short losses successfully", async function () {
		const beforeAllocatedPartyA = (await user.getBalanceInfo()).allocatedBalances
		const beforeAllocatedPartyB = (await hedger.getBalanceInfo(await user.getAddress())).allocatedBalances
		const longQuote = await context.viewFacet.getQuote(longHedger1.quoteId)
		const shortQuote = await context.viewFacet.getQuote(shortHedger1.quoteId)
		const decryptedLongQuantity = await decryptUint256(context, longQuote.quantity, context.signers.user)
		const decryptedShortQuantity = await decryptUint256(context, shortQuote.quantity, context.signers.user)

		await hedger.settleUpnl(await user.getAddress(), [decimal(5n, 17), decimal(15n, 17)], getDummySettlementSig(0n, [0n], [
			{
				quoteId: longHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput,
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: decimal(2n),
				partyBUpnlIndex: 0n
			} as QuoteSettlementDataStructOutput
		]))

		expect((await user.getBalanceInfo()).allocatedBalances).to.be.eq(beforeAllocatedPartyA - unDecimal((decryptedLongQuantity + decryptedShortQuantity) * decimal(5n, 17)))
		expect((await hedger.getBalanceInfo(await user.getAddress())).allocatedBalances).to.be.eq(beforeAllocatedPartyB + unDecimal((decryptedLongQuantity + decryptedShortQuantity) * decimal(5n, 17)))
	})

	it("Should emit encrypted partyB balances in SettleUpnl", async function () {
		const settlementSig = getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n,
			} as QuoteSettlementDataStructOutput,
		])
		await context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress)
		const tx = await context.settlementFacet.connect(context.signers.hedger).settleUpnl(
			await settlementSig,
			[decimal(5n, 17)],
			await user.getAddress(),
		)
		const receipt = await tx.wait()
		const event = receipt!.logs.find((log: any): log is EventLog => (log as EventLog).eventName === "SettleUpnl")

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

		const decryptedEmittedBalance = await context.signers.hedger.decryptUint256(emittedBalance)
		const decryptedStoredBalance = await context.signers.hedger.decryptUint256(storedBalance)
		expect(decryptedEmittedBalance).to.equal(decryptedStoredBalance)
	})

	it("Should emit BalanceChangePartyB amounts encrypted for PartyB", async function () {
		const beforeAllocatedPartyB = (await hedger.getBalanceInfo(await user.getAddress())).allocatedBalances

		// Disable trusted mode so the event keying is observable.
		await (await context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress)).wait()

		const settlementSig = getDummySettlementSig(0n, [0n], [
			{
				quoteId: shortHedger1.quoteId,
				currentPrice: 0n,
				partyBUpnlIndex: 0n,
			} as QuoteSettlementDataStructOutput,
		])
		const tx = await context.settlementFacet.connect(context.signers.hedger).settleUpnl(
			await settlementSig,
			[decimal(5n, 17)],
			await user.getAddress(),
		)
		const receipt = await tx.wait()
		const sharedEventsInterface = new ethers.Interface([
			"event BalanceChangePartyB(address indexed partyB, address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
		])
		const event = receipt!.logs
			.map((log) => {
				try {
					return sharedEventsInterface.parseLog(log)
				} catch {
					return null
				}
			})
			.find((log) => log?.name === "BalanceChangePartyB")

		expect(event).to.not.be.undefined

		const afterAllocatedBalance = await context.viewFacet.allocatedBalanceOfPartyB(await hedger.getAddress(), await user.getAddress())
		const afterAllocatedPartyB = await context.signers.hedger.decryptUint256(afterAllocatedBalance)
		const expectedAmount = beforeAllocatedPartyB - afterAllocatedPartyB
		expect(expectedAmount).to.be.gt(0n)

		const emittedAmount = event!.args.amount
		const partyBDecryptedAmount = await context.signers.hedger.decryptUint256(emittedAmount)
		expect(partyBDecryptedAmount).to.equal(expectedAmount)

		let partyACouldDecryptCorrectly = false
		try {
			const partyADecryptedAmount = await context.signers.user.decryptUint256(emittedAmount)
			partyACouldDecryptCorrectly = partyADecryptedAmount === expectedAmount
		} catch {
			partyACouldDecryptCorrectly = false
		}

		expect(partyACouldDecryptCorrectly).to.equal(false)
	})
}
