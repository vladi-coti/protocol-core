import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyHighLowPriceSig, getDummyPriceSig, getDummySingleUpnlAndPriceSig, getDummySingleUpnlSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible, timeCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

const OPEN_POSITION_COUNTS = [0, 1, 5, 10] as const
const FORCE_CLOSE_POSITION_COUNTS = [1, 5, 6, 8, 10] as const

async function openMixedPositions(context: RunContext, user: User, hedger: Hedger, count: number) {
	const quoteIds: bigint[] = []
	for (let i = 0; i < count; i++) {
		const symbolId = i % 2 === 0 ? 1 : 2
		const positionType = i % 2 === 0 ? PositionType.LONG : PositionType.SHORT
		const quantity = decimal(BigInt(10 + i))
		const price = i % 2 === 0 ? decimal(1n) : decimal(12n, 17)

		const quote = await user.sendQuote(
			limitQuoteRequestBuilder()
				.partyBWhiteList([context.signers.hedger.address])
				.affiliate(context.multiAccount)
				.symbolId(symbolId)
				.positionType(positionType)
				.quantity(quantity)
				.price(price)
				.upnlSig(getDummySingleUpnlAndPriceSig(price, 0n))
				.build(),
		)
		quoteIds.push(quote.quoteId)
		await hedger.lockQuote(quote, 0n, null)
		await hedger.openPosition(
			quote,
			limitOpenRequestBuilder()
				.filledAmount(quantity)
				.openPrice(price)
				.price(price)
				.build(),
		)
	}
	return quoteIds
}

async function setupBenchmark(count: number) {
	const context: RunContext = await loadFixtureCompatible(initializeFixture)

	await runTx(
		context.controlFacet
			.connect(context.signers.admin as any)
			.addSymbol("ETHUSDT", decimal(5n), decimal(1n, 16), decimal(1n, 16), decimal(100n), 28800, 900),
	)
	await runTx(context.controlFacet.connect(context.signers.admin as any).setDeallocateDebounceTime(0))
	await runTx(context.controlFacet.connect(context.signers.admin as any).setBalanceLimitPerUser(decimal(100000n)))
	await runTx(context.controlFacet.connect(context.signers.admin as any).setMaxPartyAOpenPositions(count > 8 ? BigInt(count) : 8n))

	const user = new User(context, context.signers.user)
	await user.setup()
	await user.setBalances(decimal(50000n), decimal(30000n), decimal(20000n))

	const hedger = new Hedger(context, context.signers.hedger)
	await hedger.setup()
	await hedger.setBalances(decimal(50000n), decimal(50000n))
	await runTx(context.accountFacet.connect(context.signers.hedger as any).allocateForPartyB(decimal(20000n), await user.getAddress()))

	const quoteIds = await openMixedPositions(context, user, hedger, count)
	return { context, user, quoteIds }
}

async function buildQuotePriceSig(context: RunContext, partyA: string) {
	const positions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
	const quoteIds = positions.map((quote: any) => BigInt(quote.id))
	const prices = positions.map((quote: any) => (BigInt(quote.symbolId) === 1n ? decimal(1n) : decimal(12n, 17)))
	return getDummyPriceSig(quoteIds, prices)
}

async function buildPartyBQuotePriceSig(context: RunContext, partyB: string, partyA: string) {
	const positions = await context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
	const quoteIds = positions.map((quote: any) => BigInt(quote.id))
	const prices = positions.map((quote: any) => (BigInt(quote.symbolId) === 1n ? decimal(1n) : decimal(12n, 17)))
	return getDummyPriceSig(quoteIds, prices)
}

async function prepareForceClose(context: RunContext, user: User, quoteId: bigint) {
	await runTx(context.controlFacet.connect(context.signers.admin as any).setForceCloseCooldowns(1, 1))
	await runTx(context.controlFacet.connect(context.signers.admin as any).setForceCloseMinSigPeriod(1))
	await runTx(context.controlFacet.connect(context.signers.admin as any).setForceClosePricePenalty(0))
	await runTx(context.controlFacet.connect(context.signers.admin as any).setForceCloseGapRatio(1, 0))
	await runTx(context.controlFacet.connect(context.signers.admin as any).setTrustedObserverAddress(ethers.ZeroAddress))

	const deadline = await getBlockTimestamp() + 30n
	await user.requestToClosePosition(
		quoteId,
		limitCloseRequestBuilder()
			.quantityToClose(await getQuoteQuantity(context, quoteId))
			.closePrice(decimal(1n))
			.deadline(deadline)
			.build(),
	)

	const quote = await context.viewFacet.getQuote(quoteId)
	const startTime = quote.statusModifyTimestamp + 1n
	const endTime = startTime + 1n
	await timeCompatible.increase(endTime + 2n - await getBlockTimestamp())
	return getDummyHighLowPriceSig(startTime, endTime, 0n, decimal(1n), decimal(1n), decimal(1n), 0n, 0n, 0n)
}

export function shouldBehaveLikeAuditH01(): void {
	describe("Muon UPNL plaintext calldata", function () {
		it("H-01: state-changing Muon calldata structs do not expose UPNL/risk fields", async function () {
			const sig = await getDummySingleUpnlSig(-123456789n)
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const calldata = context.accountFacet.interface.encodeFunctionData("deallocate", [1n, sig])
			const decoded = context.accountFacet.interface.decodeFunctionData("deallocate", calldata)
			expect(decoded[1].upnl).to.equal(undefined)

			const src = fs.readFileSync(path.join(__dirname, "../../contracts/storages/MuonStorage.sol"), "utf8")
			for (const field of ["int256 upnl;", "int256 upnlPartyA;", "int256 upnlPartyB;", "int256[] upnlPartyBs;", "int256 totalUnrealizedLoss;"]) {
				expect(src).not.to.include(field)
			}
		})

		for (const count of OPEN_POSITION_COUNTS) {
			it(`H-01 gas: deallocate baseline vs computed UPNL with ${count} open positions`, async function () {
				const { context, user } = await setupBenchmark(count)
				const amount = decimal(1n)
				const priceSig = await buildQuotePriceSig(context, await user.getAddress())
				const baselineTx = await context.accountFacet
					.connect(context.signers.user as any)
					.deallocate(amount, priceSig)
				const baselineReceipt = await baselineTx.wait()
				const baselineGas = baselineReceipt!.gasUsed

				const computedTx = await context.accountFacet
					.connect(context.signers.user as any)
					.deallocateWithQuotePrices(amount, priceSig)
				const computedReceipt = await computedTx.wait()
				const computedGas = computedReceipt!.gasUsed

				console.log(`[H-01 gas] mode=price-only path=deallocate openPositions=${count} gas=${baselineGas.toString()}`)
				console.log(`[H-01 gas] mode=computed path=deallocate openPositions=${count} gas=${computedGas.toString()}`)
				expect(baselineGas).to.be.gt(0n)
				expect(computedGas).to.be.gt(0n)
			})
		}

		for (const count of FORCE_CLOSE_POSITION_COUNTS) {
			it(`H-01 gas: force-close baseline vs computed UPNL with ${count} open positions`, async function () {
				const baseline = await setupBenchmark(count)
				const baselineSig = await prepareForceClose(baseline.context, baseline.user, baseline.quoteIds[0])
				const baselinePartyA = await baseline.user.getAddress()
				const baselinePartyB = baseline.context.signers.hedger.address
				const baselineTx = await baseline.context.forceCloseFacet
					.connect(baseline.context.signers.user as any)
					.forceClosePosition(
						baseline.quoteIds[0],
						baselineSig,
						await buildQuotePriceSig(baseline.context, baselinePartyA),
						await buildPartyBQuotePriceSig(baseline.context, baselinePartyB, baselinePartyA),
					)
				const baselineReceipt = await baselineTx.wait()
				const baselineGas = baselineReceipt!.gasUsed

				const computed = await setupBenchmark(count)
				const partyA = await computed.user.getAddress()
				const partyB = computed.context.signers.hedger.address
				const computedSig = await prepareForceClose(computed.context, computed.user, computed.quoteIds[0])
				const forceCloseWithPrices = new ethers.Interface([
					"function forceClosePositionWithQuotePrices(uint256 quoteId,(bytes reqId,uint256 timestamp,uint256 symbolId,uint256 highest,uint256 lowest,uint256 averagePrice,uint256 startTime,uint256 endTime,uint256 currentPrice,bytes gatewaySignature,(uint256 signature,address owner,address nonce) sigs) sig,(bytes reqId,uint256 timestamp,uint256[] quoteIds,uint256[] prices,bytes gatewaySignature,(uint256 signature,address owner,address nonce) sigs) partyAPriceSig,(bytes reqId,uint256 timestamp,uint256[] quoteIds,uint256[] prices,bytes gatewaySignature,(uint256 signature,address owner,address nonce) sigs) partyBPriceSig)",
				])
				const computedTx = await computed.context.signers.user.sendTransaction({
					to: computed.context.diamond,
					data: forceCloseWithPrices.encodeFunctionData("forceClosePositionWithQuotePrices", [
					computed.quoteIds[0],
					computedSig,
					await buildQuotePriceSig(computed.context, partyA),
					await buildPartyBQuotePriceSig(computed.context, partyB, partyA),
					]),
				})
				const computedReceipt = await computedTx.wait()
				const computedGas = computedReceipt!.gasUsed

				console.log(`[H-01 gas] mode=price-only path=forceClose openPositions=${count} gas=${baselineGas.toString()}`)
				console.log(`[H-01 gas] mode=computed path=forceClose openPositions=${count} gas=${computedGas.toString()}`)
				expect(baselineGas).to.be.gt(0n)
				expect(computedGas).to.be.gt(0n)
			})
		}
	})
}
