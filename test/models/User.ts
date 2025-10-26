import {setBalance} from "@nomicfoundation/hardhat-network-helpers"
import {BigNumberish, ethers, EventLog} from "ethers"
import {Wallet, ctUint256, itUint256} from "@coti-io/coti-ethers"

import {getPriceFetcher, serializeToJson, unDecimal} from "../utils/Common"
import {logger} from "../utils/LoggerUtils"
import {getPrice} from "../utils/PriceUtils"
import {PositionType} from "./Enums"
import {RunContext} from "./RunContext"
import {CloseRequest, limitCloseRequestBuilder} from "./requestModels/CloseRequest"
import {limitQuoteRequestBuilder, QuoteRequest} from "./requestModels/QuoteRequest"
import {runTx} from "../utils/TxUtils"
import {getDummyLiquidationSig} from "../utils/SignatureUtils"
import {LiquidationSigStruct} from "../../src/types/contracts/facets/liquidation/LiquidationFacet"
import {PrivateQuoteParamsStruct, QuoteBasicParamsStruct, QuoteStructOutput, SettlementSigStruct, SendQuoteForPartyBEvent} from "../../src/types/contracts/interfaces/ISymmio"
import {HighLowPriceSigStruct} from "../../src/types/contracts/facets/ForceActions/ForceActionsFacet"
import {QuoteData} from "./types"

export class User {
	constructor(protected context: RunContext, protected signer: Wallet) {
	}

	public async setup() {
		await this.context.manager.registerUser(this)
	}

	public getWallet(): Wallet {
		return this.signer
	}

	public async encryptUint256(value: bigint, contractAddress: string, selector: string): Promise<itUint256> {
		return await this.signer.encryptUint256(value, contractAddress, selector)
	}

	public async decryptUint256(ciphertext: ctUint256): Promise<bigint> {
		return await this.signer.decryptUint256(ciphertext)
	}

	public async setBalances(collateralAmount?: BigNumberish, depositAmount?: BigNumberish, allocatedAmount?: BigNumberish) {
		const userAddress = this.signer.getAddress()

		await runTx(this.context.collateral.connect(this.signer).approve(this.context.diamond, ethers.MaxUint256))

		if (collateralAmount) await runTx(this.context.collateral.connect(this.signer).mint(userAddress, collateralAmount))
		if (depositAmount) await runTx(this.context.accountFacet.connect(this.signer).deposit(depositAmount))
		if (allocatedAmount) await runTx(this.context.accountFacet.connect(this.signer).allocate(allocatedAmount))
	}

	public async setNativeBalance(amount: bigint) {
		await setBalance(this.signer.address, amount)
	}

	public async sendQuote(request: QuoteRequest = limitQuoteRequestBuilder().partyBWhiteList([this.context.signers.hedger.address]).affiliate(this.context.multiAccount).build()): Promise<QuoteData> {
		logger.detailedDebug(
			serializeToJson({
				request: request,
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)

		const basicParams: QuoteBasicParamsStruct = {
			partyBsWhiteList: request.partyBWhiteList,
			symbolId: request.symbolId,
			positionType: request.positionType,
			orderType: request.orderType,
			maxFundingRate: request.maxFundingRate,
			deadline: await request.deadline,
			affiliate: request.affiliate,
		}

		const contractAddress = this.context.diamond
		const selector = this.context.partyAFacet.interface.getFunction("sendQuote").selector

		const encryptedPrice = await this.encryptUint256(BigInt(request.price), contractAddress, selector);
		const encryptedQuantity = await this.encryptUint256(BigInt(request.quantity), contractAddress, selector);
		const encryptedCva = await this.encryptUint256(BigInt(request.cva), contractAddress, selector);
		const encryptedLf = await this.encryptUint256(BigInt(request.lf), contractAddress, selector);
		const encryptedPartyAmm = await this.encryptUint256(BigInt(request.partyAmm), contractAddress, selector);
		const encryptedPartyBmm = await this.encryptUint256(BigInt(request.partyBmm), contractAddress, selector);

		const encryptedParams: PrivateQuoteParamsStruct = {
			encryptedPrice: encryptedPrice,
			encryptedQuantity: encryptedQuantity,
			encryptedCva: encryptedCva,
			encryptedLf: encryptedLf,
			encryptedPartyAmm: encryptedPartyAmm,
			encryptedPartyBmm: encryptedPartyBmm,
		};

		let tx = await this.context.partyAFacet.connect(this.signer).sendQuote(basicParams, encryptedParams, await request.upnlSig)
		console.log("User::::SendQuote: " + tx.hash)
		const receipt = await tx.wait()

		let quoteId: bigint = 0n
		let partyBEvent: SendQuoteForPartyBEvent.OutputObject | undefined
		if (receipt && receipt.logs) {
			console.log("User::::Receipt gas used: " + receipt.gasUsed.toString())
		
			const SendQuoteForPartyA = receipt.logs.find((log: any): log is EventLog => {
				return (log as EventLog).eventName === "SendQuoteForPartyA"
			})

			if (SendQuoteForPartyA && SendQuoteForPartyA.args) {
				const id = SendQuoteForPartyA.args.quoteId
				console.log("User::::SendQuote: " + id)
				quoteId = id
			}

			const SendQuoteForPartyB = receipt.logs.find((log: any): log is EventLog => {
				return (log as EventLog).eventName === "SendQuoteForPartyB"
			})

			if (SendQuoteForPartyB && SendQuoteForPartyB.args) {
				// Convert raw event args to proper structure
				const args = SendQuoteForPartyB.args as any[]
				const rawValues = args[6] // The EncryptedQuoteValues struct is at index 6
				
				partyBEvent = {
					partyA: args[0],
					quoteId: args[1],
					partyB: args[2],
					symbolId: args[3],
					positionType: args[4],
					orderType: args[5],
					values: this.formatEncryptedQuoteValues(rawValues),
					deadline: args[7]
				} as SendQuoteForPartyBEvent.OutputObject
				console.log("User::::SendQuoteForPartyBEvent: ", partyBEvent.quoteId)
			}
		}
		if (quoteId == 0n) {
			throw new Error("SendQuoteForPartyA event not found in transaction receipt")
		}
		return { quoteId, partyBEvent }
	}

	private convertRawCiphertextToCtUint256(rawCiphertext: [bigint, bigint]): { ciphertextHigh: bigint, ciphertextLow: bigint } {
		return {
			ciphertextHigh: rawCiphertext[0],
			ciphertextLow: rawCiphertext[1]
		}
	}

	private formatEncryptedQuoteValues(rawValues: any[]): any {
		return {
			price: this.convertRawCiphertextToCtUint256(rawValues[0]),
			marketPrice: this.convertRawCiphertextToCtUint256(rawValues[1]),
			quantity: this.convertRawCiphertextToCtUint256(rawValues[2]),
			cva: this.convertRawCiphertextToCtUint256(rawValues[3]),
			lf: this.convertRawCiphertextToCtUint256(rawValues[4]),
			partyAmm: this.convertRawCiphertextToCtUint256(rawValues[5]),
			partyBmm: this.convertRawCiphertextToCtUint256(rawValues[6]),
			tradingFee: this.convertRawCiphertextToCtUint256(rawValues[7])
		}
	}

	public async requestToCancelQuote(id: BigNumberish) {
		logger.detailedDebug(
			serializeToJson({
				request: "RequestToCancelQuote",
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)
		await runTx(this.context.partyAFacet.connect(this.signer).requestToCancelQuote(id))
		logger.info(`User::::RequestToCancelQuote: ${id}`)
	}

	public async forceCancelQuote(id: BigNumberish) {
		logger.detailedDebug(
			serializeToJson({
				request: "ForceCancelQuote",
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)
		await runTx(this.context.forceActionsFacet.connect(this.signer).forceCancelQuote(id))
		logger.info(`User::::ForceCancelQuote: ${id}`)
	}

	public async forceCancelCloseRequest(id: BigNumberish) {
		logger.detailedDebug(
			serializeToJson({
				request: "ForceCancelCloseRequest",
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)
		await runTx(this.context.forceActionsFacet.connect(this.signer).forceCancelCloseRequest(id))
		logger.info(`User::::ForceCancelCloseRequest: ${id}`)
	}

	public async getBalanceInfo(): Promise<BalanceInfo> {
		const result = await this.context.viewFacet.balanceInfoOfPartyA(await this.getAddress())
		const allocatedBalances = await this.decryptUint256(result[0])
		const lockedBalances = result[1]
		const pendingLockedBalances = result[2]
		
		// Decrypt the encrypted locked values
		const lockedCva = await this.decryptUint256(lockedBalances.cva)
		const lockedLf = await this.decryptUint256(lockedBalances.lf)
		const lockedMmPartyA = await this.decryptUint256(lockedBalances.partyAmm)
		const lockedMmPartyB = await this.decryptUint256(lockedBalances.partyBmm)
		
		const pendingLockedCva = await this.decryptUint256(pendingLockedBalances.cva)
		const pendingLockedLf = await this.decryptUint256(pendingLockedBalances.lf)
		const pendingLockedMmPartyA = await this.decryptUint256(pendingLockedBalances.partyAmm)
		const pendingLockedMmPartyB = await this.decryptUint256(pendingLockedBalances.partyBmm)

		return {
			allocatedBalances,
			lockedCva,
			lockedLf,
			lockedMmPartyA,
			lockedMmPartyB,
			totalLockedPartyA: lockedCva + lockedLf + lockedMmPartyA,
			totalLockedPartyB: lockedCva + lockedLf + lockedMmPartyB,
			pendingLockedCva,
			pendingLockedLf,
			pendingLockedMmPartyA,
			pendingLockedMmPartyB,
			totalPendingLockedPartyA: pendingLockedCva + pendingLockedLf + pendingLockedMmPartyA,
			totalPendingLockedPartyB: pendingLockedCva + pendingLockedLf + pendingLockedMmPartyB,
		}
	}


	public async requestToClosePosition(id: BigNumberish, request: CloseRequest = limitCloseRequestBuilder().build()) {
		logger.detailedDebug(
			serializeToJson({
				request: request,
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)

		const contractAddress = this.context.diamond
		const selector = this.context.partyAFacet.interface.getFunction("requestToClosePosition").selector

		const encryptedClosePrice = await this.encryptUint256(BigInt(request.closePrice), contractAddress, selector);
		const encryptedQuantityToClose = await this.encryptUint256(BigInt(request.quantityToClose), contractAddress, selector);

		await runTx(
			this.context.partyAFacet
				.connect(this.signer)
				.requestToClosePosition(id, encryptedClosePrice, encryptedQuantityToClose, request.orderType, await request.deadline),
		)
		logger.info(`User::::RequestToClosePosition: ${id}`)
	}

	public async forceClosePosition(id: BigNumberish, signature: HighLowPriceSigStruct) {
		logger.detailedDebug(
			serializeToJson({
				signature: signature,
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)
		await runTx(this.context.forceActionsFacet.connect(this.signer).forceClosePosition(id, signature))
		logger.info(`User::::ForceClosePosition: ${id}`)
	}

	public async settleAndForceClosePosition(id: BigNumberish, highLowPriceSigStruct: HighLowPriceSigStruct, settleSig: SettlementSigStruct, updatedPrices: bigint[]) {
		logger.detailedDebug(
			serializeToJson({
				highLowPriceSigStruct: highLowPriceSigStruct,
				settleSig: settleSig,
				updatedPrices: updatedPrices,
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)
		await runTx(this.context.forceActionsFacet.connect(this.signer).settleAndForceClosePosition(id, highLowPriceSigStruct, settleSig, updatedPrices))
		logger.info(`User::::SettleAndForceClosePosition: ${id}`)
	}

	public async requestToCancelCloseRequest(id: BigNumberish) {
		logger.detailedDebug(
			serializeToJson({
				request: "RequestToCancelCloseRequest",
				userBalanceInfo: await this.getBalanceInfo(),
				userUpnl: await this.getUpnl(),
			}),
		)
		await runTx(this.context.partyAFacet.connect(this.signer).requestToCancelCloseRequest(id))
		logger.info(`User::::RequestToCancelCloseRequest: ${id}`)
	}

	public getAddress() {
		return this.signer.getAddress()
	}

	public async getUpnl(
		symbolIdPriceFetcher: ((symbolId: bigint) => Promise<bigint>) | null = null,
		symbolNamePriceFetcher: (symbol: string) => Promise<bigint> = getPrice,
	): Promise<bigint> {
		let openPositions = await this.getOpenPositions()
		let upnl = 0n
		for (const pos of openPositions) {
			// Decrypt encrypted quote fields
			const openedPrice = await this.decryptUint256(pos.openedPrice.userCiphertext)
			const quantity = await this.decryptUint256(pos.quantity.userCiphertext)
			const closedAmount = await this.decryptUint256(pos.closedAmount.userCiphertext)
			
			const priceDiff = openedPrice - (
				symbolIdPriceFetcher != null
					? await symbolIdPriceFetcher(pos.symbolId)
					: await symbolNamePriceFetcher((await this.context.viewFacet.getSymbol(pos.symbolId)).name)
			)
			const amount = quantity - closedAmount
			upnl += unDecimal(amount * priceDiff) * (pos.positionType == BigInt(PositionType.LONG) ? -1n : 1n)
		}
		return upnl
	}

	public async getTotalUnrealisedLoss(
		symbolIdPriceFetcher: ((symbolId: bigint) => Promise<bigint>) | null = null,
		symbolNamePriceFetcher: (symbol: string) => Promise<bigint> = getPrice,
	): Promise<bigint> {
		let openPositions = await this.getOpenPositions()
		let upnl = 0n
		for (const pos of openPositions) {
			// Decrypt encrypted quote fields
			const openedPrice = await this.decryptUint256(pos.openedPrice.userCiphertext)
			const quantity = await this.decryptUint256(pos.quantity.userCiphertext)
			const closedAmount = await this.decryptUint256(pos.closedAmount.userCiphertext)
			
			const priceDiff = openedPrice - (
				symbolIdPriceFetcher != null
					? await symbolIdPriceFetcher(pos.symbolId)
					: await symbolNamePriceFetcher((await this.context.viewFacet.getSymbol(pos.symbolId)).name)
			)
			const amount = quantity - closedAmount
			upnl += unDecimal(amount * priceDiff) * (pos.positionType == BigInt(PositionType.LONG) ? 0n : 1n)
		}
		return upnl
	}

	public async getAvailableBalanceForQuote(upnl: bigint): Promise<bigint> {
		const balanceInfo = await this.getBalanceInfo()
		let available: bigint
		if (upnl > 0n) {
			available = balanceInfo.allocatedBalances + upnl - (balanceInfo.totalLockedPartyA + balanceInfo.totalPendingLockedPartyA)
		} else {
			let mm = balanceInfo.lockedMmPartyA
			let mUpnl = -upnl
			let considering_mm = mUpnl > mm ? mUpnl : mm
			available = balanceInfo.allocatedBalances
				- (balanceInfo.lockedCva + balanceInfo.lockedLf + balanceInfo.totalPendingLockedPartyA)
				- considering_mm
		}
		return available
	}

	public async liquidateAndSetSymbolPrices(
		symbolIds: bigint[],
		prices: bigint[],
		liquidator: Wallet = this.context.signers.liquidator,
	): Promise<LiquidationSigStruct> {
		const upnl = await this.getUpnl(getPriceFetcher(symbolIds, prices))
		const totalUnrealizedLoss = await this.getTotalUnrealisedLoss(getPriceFetcher(symbolIds, prices))
		const allocatedBalance = (await this.getBalanceInfo()).allocatedBalances
		const sign = await getDummyLiquidationSig("0x10", upnl, symbolIds, prices, totalUnrealizedLoss, allocatedBalance)
		await this.context.liquidationFacet.connect(liquidator).liquidatePartyA(this.getAddress(), sign)
		await this.context.liquidationFacet.connect(liquidator).setSymbolsPrice(this.getAddress(), sign)
		return sign
	}

	public async liquidatePendingPositions(liquidator: Wallet = this.context.signers.liquidator) {
		await this.context.liquidationFacet.connect(liquidator).liquidatePendingPositionsPartyA(this.getAddress())
	}

	public async liquidatePositions(positions: BigNumberish[] = [], liquidator: Wallet = this.context.signers.liquidator) {
		if (positions.length == 0) positions = (await this.getOpenPositions()).map(value => value.id)
		await this.context.liquidationFacet.connect(liquidator).liquidatePositionsPartyA(this.getAddress(), positions)
	}

	public async getOpenPositions(): Promise<QuoteStructOutput[]> {
		let openPositions: QuoteStructOutput[] = []
		const pageSize = 30
		let last = 0
		while (true) {
			let page = await this.context.viewFacet.getPartyAOpenPositions(this.getAddress(), last, pageSize)
			openPositions.push(...page)
			if (page.length < pageSize) break
		}
		return openPositions
	}

	public async settleLiquidation(
		partyB: Wallet = this.context.signers.hedger,
		liquidator: Wallet = this.context.signers.liquidator,
	): Promise<void> {
		await this.context.liquidationFacet.connect(liquidator).settlePartyALiquidation(await this.getAddress(), [await partyB.getAddress()])
	}

	public async getLiquidatedStateOfPartyA() {
		return this.context.viewFacet.getLiquidatedStateOfPartyA(await this.getAddress())
	}
}

export interface BalanceInfo {
	allocatedBalances: bigint
	lockedCva: bigint
	lockedMmPartyA: bigint
	lockedMmPartyB: bigint
	lockedLf: bigint
	totalLockedPartyA: bigint
	totalLockedPartyB: bigint
	pendingLockedCva: bigint
	pendingLockedMmPartyA: bigint
	pendingLockedMmPartyB: bigint
	pendingLockedLf: bigint
	totalPendingLockedPartyA: bigint
	totalPendingLockedPartyB: bigint
}
