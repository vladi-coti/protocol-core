import {setBalance} from "@nomicfoundation/hardhat-network-helpers"
import {BigNumberish, ethers, EventLog} from "ethers"

import {decimal, serializeToJson, unDecimal} from "../utils/Common"
import {logger} from "../utils/LoggerUtils"
import {getPrice} from "../utils/PriceUtils"
import {getDummyPairUpnlAndPriceSig, getDummySettlementSig, getDummySingleUpnlSig} from "../utils/SignatureUtils"
import {PositionType} from "./Enums"
import {RunContext} from "./RunContext"
import {EmergencyCloseRequest, emergencyCloseRequestBuilder} from "./requestModels/EmergencyCloseRequest"
import {FillCloseRequest, limitFillCloseRequestBuilder} from "./requestModels/FillCloseRequest"
import {limitOpenRequestBuilder, OpenRequest} from "./requestModels/OpenRequest"
import {runTx} from "../utils/TxUtils"
import {PairUpnlSigStructOutput} from "../../src/types/contracts/facets/FundingRate/FundingRateFacet"
import {Wallet} from "@coti-io/coti-ethers"
import {
	PairUpnlAndPriceSigStruct,
	PrivateClosePositionParamsStruct,
	PrivateOpenPositionParamsStruct,
	QuoteStructOutput,
	SendQuoteForPartyBEvent,
	SettlementSigStructOutput,
	SingleUpnlSigStruct,
} from "../../src/types/contracts/interfaces/ISymmio"
import { QuoteData } from "./types";

export class Hedger {
	constructor(private context: RunContext, private signer: Wallet) {
	}

	public async setup() {
		await this.context.manager.registerHedger(this)
	}

	public async setBalances(collateralAmount?: BigNumberish, depositAmount?: BigNumberish) {
		const userAddress = await this.signer.getAddress()
		await runTx(this.context.collateral.connect(this.signer).approve(this.context.diamond, ethers.MaxUint256))

		if (collateralAmount) {
			const currentCollateral = await this.context.collateral.balanceOf(userAddress)
			if (currentCollateral < BigInt(collateralAmount.toString())) {
				const needed = BigInt(collateralAmount.toString()) - currentCollateral
				await runTx(this.context.collateral.connect(this.signer).mint(userAddress, needed))
			}
		}
		
		if (depositAmount) {
			const currentDeposited = await this.context.viewFacet.balanceOf(userAddress)
			if (currentDeposited < BigInt(depositAmount.toString())) {
				const needed = BigInt(depositAmount.toString()) - currentDeposited
				await runTx(this.context.accountFacet.connect(this.signer).deposit(needed))
			}
		}
	}

	public async depositToReserveVault(amount: BigNumberish) {
		await runTx(this.context.collateral.connect(this.signer).approve(this.context.diamond, ethers.MaxUint256))
		await runTx(this.context.accountFacet.connect(this.signer).depositToReserveVault(amount, await this.signer.getAddress()))
	}

	public async withdrawFromReserveVault(amount: BigNumberish) {
		await runTx(this.context.accountFacet.connect(this.signer).withdrawFromReserveVault(amount))
	}

	public async balanceOfReserveVault(): Promise<bigint> {
		return await this.context.viewFacet.connect(this.signer).balanceOfReserveVault(await this.signer.getAddress())
	}

	public async setNativeBalance(amount: bigint) {
		await setBalance(this.signer.address, amount)
	}

	public async register() {
		const hedgerAddress = await this.signer.getAddress()
		
		// Check if already registered
		const isRegistered = await this.context.viewFacet.isPartyB(hedgerAddress)
		if (isRegistered) {
			return
		}
		
		const tx = await this.context.controlFacet.connect(this.context.signers.admin).registerPartyB(hedgerAddress)
		await tx.wait()
	}

	private async decryptQuoteData(partyBEvent: SendQuoteForPartyBEvent.OutputObject): Promise<{quantity: bigint, price: bigint, partyA: string}> {
		const { values } = partyBEvent
		const { price, quantity } = values
		const quantityDecrypted = await this.signer.decryptUint256(quantity)
		const priceDecrypted = await this.signer.decryptUint256(price)
		return { quantity: quantityDecrypted, price: priceDecrypted, partyA: partyBEvent.partyA }
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

	private convertRawCiphertextToCtUint256(rawCiphertext: [bigint, bigint]): { ciphertextHigh: bigint, ciphertextLow: bigint } {
		return {
			ciphertextHigh: rawCiphertext[0],
			ciphertextLow: rawCiphertext[1]
		}
	}

	private async fetchPartyBEventFromQuote(quoteId: bigint): Promise<SendQuoteForPartyBEvent.OutputObject> {
		// Query SendQuoteForPartyB events filtered by quoteId
		// Filter signature: SendQuoteForPartyB(address partyA, uint256 quoteId, address partyB, ...)
		const filter = this.context.partyAFacet.filters.SendQuoteForPartyB(undefined, quoteId)
		const events = await this.context.partyAFacet.queryFilter(filter)
		
		if (events.length === 0) {
			throw new Error(`SendQuoteForPartyB event not found for quoteId: ${quoteId}`)
		}

		// Get the most recent event for this quoteId (in case there are multiple)
		const event = events[events.length - 1]
		if (!event.args) {
			throw new Error(`SendQuoteForPartyB event has no args for quoteId: ${quoteId}`)
		}

		const args = event.args as any[]
		const rawValues = args[6] // The EncryptedQuoteValues struct is at index 6
		
		return {
			partyA: args[0],
			quoteId: args[1],
			partyB: args[2],
			symbolId: args[3],
			positionType: args[4],
			orderType: args[5],
			values: this.formatEncryptedQuoteValues(rawValues) as SendQuoteForPartyBEvent.OutputObject["values"],
			deadline: args[7]
		} as SendQuoteForPartyBEvent.OutputObject
	}

	public async lockQuote(quoteData: QuoteData, upnl: bigint = 0n, allocateCoefficient: bigint | null = decimal(12n, 17)) {
		const { quoteId: id } = quoteData
		let partyBEvent = quoteData.partyBEvent

		if (allocateCoefficient != null) {
			// If partyBEvent is undefined, try to fetch it from the contract
			if (partyBEvent == undefined) {
				partyBEvent = await this.fetchPartyBEventFromQuote(id)
			}

			if (partyBEvent == undefined) {
				throw new Error(`PartyBEvent is required for allocation but could not be found for quoteId: ${id}`)
			}

			const { partyA } = partyBEvent
			const { price, quantity } = await this.decryptQuoteData(partyBEvent)
			const notional = unDecimal(quantity * price)
			await runTx(
				this.context.accountFacet.connect(this.signer).allocateForPartyB(unDecimal(notional * BigInt(allocateCoefficient)), partyA)
			)
		}
		await runTx(this.context.partyBQuoteActionsFacet.connect(this.signer).lockQuote(id, await getDummySingleUpnlSig(upnl)))

		logger.info(`Hedger::LockQuote: ${id}`)
	}

	public async unlockQuote(id: BigNumberish) {
		await runTx(this.context.partyBQuoteActionsFacet.connect(this.signer).unlockQuote(id))
		logger.info(`Hedger::UnLockQuote: ${id}`)
	}

	public async lockAndOpenQuote(quoteData: QuoteData, allocateCoefficient: bigint | null = decimal(12n, 17), openRequest: OpenRequest = limitOpenRequestBuilder().build()) {
		const { quoteId: id } = quoteData
		if (allocateCoefficient != null) {
			if(quoteData.partyBEvent == undefined) {
				throw new Error("PartyBEvent is undefined")
			}
			const { partyA } = quoteData.partyBEvent
			const { price, quantity } = await this.decryptQuoteData(quoteData.partyBEvent)
			const notional = unDecimal(quantity * price)
			await runTx(
				this.context.accountFacet.connect(this.signer).allocateForPartyB(unDecimal(notional * BigInt(allocateCoefficient)), partyA)
			)
		}
		await runTx(
			this.context.partyBGroupActionsFacet.connect(this.signer)
				.lockAndOpenQuote(
					id,
					openRequest.filledAmount,
					openRequest.openPrice,
					await getDummySingleUpnlSig(BigInt(openRequest.upnlPartyA)),
					await getDummyPairUpnlAndPriceSig(BigInt(openRequest.price), BigInt(openRequest.upnlPartyA), BigInt(openRequest.upnlPartyB))
				)
		)
	}

	public async buildOpenPositionCalldataArgs(
		request: OpenRequest,
		selector: string = this.context.partyBPositionActionsFacet.interface.getFunction("openPosition").selector,
	): Promise<{
		encryptedParams: PrivateOpenPositionParamsStruct
		upnlSig: PairUpnlAndPriceSigStruct
	}> {
		const contractAddress = this.context.diamond

		const encryptedFilledAmount = await this.signer.encryptUint256(BigInt(request.filledAmount), contractAddress, selector)
		const encryptedOpenedPrice = await this.signer.encryptUint256(BigInt(request.openPrice), contractAddress, selector)

		return {
			encryptedParams: {
				encryptedFilledAmount,
				encryptedOpenedPrice,
			},
			upnlSig: await getDummyPairUpnlAndPriceSig(BigInt(request.price), BigInt(request.upnlPartyA), BigInt(request.upnlPartyB)),
		}
	}

	public async openPosition(quoteData: QuoteData | { quoteId: bigint; partyA: string }, request: OpenRequest = limitOpenRequestBuilder().build()) {
		let partyA: string
		if ('partyBEvent' in quoteData && quoteData.partyBEvent) {
			partyA = quoteData.partyBEvent.partyA
		} else if ('partyA' in quoteData) {
			partyA = quoteData.partyA
		} else {
			throw new Error("PartyA is required - provide either partyBEvent or partyA directly")
		}
		const user = this.context.manager.getUser(partyA)
		logger.detailedDebug(
			serializeToJson({
				request: request,
				hedgerBalanceInfo: await this.getBalanceInfo(partyA),
				hedgerUpnl: await this.getUpnl(partyA),
				userBalanceInfo: await user.getBalanceInfo(),
				userUpnl: await user.getUpnl(),
			})
		)
		
		const {encryptedParams, upnlSig} = await this.buildOpenPositionCalldataArgs(request)
		
		const tx = await runTx(
			this.context.partyBPositionActionsFacet
				.connect(this.signer)
				.openPosition(
					quoteData.quoteId,
					encryptedParams,
					upnlSig
				)
		)
		logger.info(`Hedger::OpenPosition: ${quoteData.quoteId} gas used: ${tx.gasUsed.toString()}`)
	}

	public async getBalance(): Promise<bigint> {
		return await this.context.viewFacet.balanceOf(await this.getAddress())
	}

	public async getBalanceInfo(partyA: string): Promise<BalanceInfo> {
		const result = await this.context.viewFacet.balanceInfoOfPartyB(this.signer.address, partyA)
		const allocatedBalances = await this.signer.decryptUint256(result[0])
		const lockedBalances = result[1]
		const pendingLockedBalances = result[2]
		
		// Decrypt the encrypted locked values
		const lockedCva = await this.signer.decryptUint256(lockedBalances.cva)
		const lockedLf = await this.signer.decryptUint256(lockedBalances.lf)
		const lockedMmPartyA = await this.signer.decryptUint256(lockedBalances.partyAmm)
		const lockedMmPartyB = await this.signer.decryptUint256(lockedBalances.partyBmm)
		
		const pendingLockedCva = await this.signer.decryptUint256(pendingLockedBalances.cva)
		const pendingLockedLf = await this.signer.decryptUint256(pendingLockedBalances.lf)
		const pendingLockedMmPartyA = await this.signer.decryptUint256(pendingLockedBalances.partyAmm)
		const pendingLockedMmPartyB = await this.signer.decryptUint256(pendingLockedBalances.partyBmm)
		
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

	public async acceptCancelRequest(id: BigNumberish) {
		await runTx(this.context.partyBQuoteActionsFacet.connect(this.signer).acceptCancelRequest(id))
		logger.info(`Hedger::AcceptCancelRequest: ${id}`)
	}

	public async buildFillCloseRequestCalldataArgs(
		request: FillCloseRequest,
		selector: string = this.context.partyBPositionActionsFacet.interface.getFunction("fillCloseRequest").selector,
	): Promise<{
		encryptedParams: PrivateClosePositionParamsStruct
		upnlSig: PairUpnlAndPriceSigStruct
	}> {
		const contractAddress = this.context.diamond

		const encryptedFilledAmount = await this.signer.encryptUint256(BigInt(request.filledAmount), contractAddress, selector)
		const encryptedClosedPrice = await this.signer.encryptUint256(BigInt(request.closedPrice), contractAddress, selector)

		return {
			encryptedParams: {
				encryptedFilledAmount,
				encryptedClosedPrice,
			},
			upnlSig: await getDummyPairUpnlAndPriceSig(BigInt(request.price), BigInt(request.upnlPartyA), BigInt(request.upnlPartyB)),
		}
	}

	public async fillCloseRequest(id: BigNumberish, request: FillCloseRequest = limitFillCloseRequestBuilder().build()) {
		const quote = await this.context.viewFacet.getQuote(id)
		const user = this.context.manager.getUser(quote.partyA)
		logger.detailedDebug(
			serializeToJson({
				request: request,
				hedgerBalanceInfo: await this.getBalanceInfo(quote.partyA),
				hedgerUpnl: await this.getUpnl(quote.partyA),
				userBalanceInfo: await user.getBalanceInfo(),
				userUpnl: await user.getUpnl(),
			})
		)
		const {encryptedParams, upnlSig} = await this.buildFillCloseRequestCalldataArgs(request)
		
		const tx = await this.context.partyBPositionActionsFacet
				.connect(this.signer)
				.fillCloseRequest(
					id,
					encryptedParams,
					upnlSig
				)

		console.log("Hedger::FillCloseRequest: tx: ", tx)
		const receipt = await tx.wait()
		if (!receipt) {
			throw new Error("FillCloseRequest failed")
		}
		const DebugCloseQuotePnl = receipt.logs.find((log: any): log is EventLog => {
			return (log as EventLog).eventName === "DebugCloseQuotePnl"
		})

		if (DebugCloseQuotePnl && DebugCloseQuotePnl.args) {
			const args = DebugCloseQuotePnl.args as any[]
			const quoteId = args[0]
			const partyA = args[1]
			const partyB = args[2]
			const hasMadeProfit = args[3]
			const pnl = args[4]
			const partyBBalance = args[5]
			console.log("Hedger::DebugCloseQuotePnl: quoteId: ", quoteId)
			console.log("Hedger::DebugCloseQuotePnl: partyA: ", partyA)
			console.log("Hedger::DebugCloseQuotePnl: partyB: ", partyB)
			console.log("Hedger::DebugCloseQuotePnl: hasMadeProfit: ", hasMadeProfit)
			console.log("Hedger::DebugCloseQuotePnl: pnl: ", pnl)
			console.log("Hedger::DebugCloseQuotePnl: partyBBalance: ", partyBBalance.toString())
		}
		
		logger.info(`Hedger::FillCloseRequest: ${id}, gas used: ${receipt.gasUsed.toString()}`)
	}

	public async chargeFundingRate(partyA: string, quoteIds: BigNumberish[], rates: BigNumberish[], signature: PairUpnlSigStructOutput) {
		await this.context.fundingRateFacet.connect(this.signer).chargeFundingRate(partyA, quoteIds, rates, signature)
		logger.info(`Hedger::ChargeFundingRate: ${partyA}, ${quoteIds}, ${rates}`)
	}

	public async acceptCancelCloseRequest(id: BigNumberish) {
		await runTx(this.context.partyBPositionActionsFacet.connect(this.signer).acceptCancelCloseRequest(id))
		logger.info(`Hedger::AcceptCancelCloseRequest: ${id}`)
	}

	public async liquidate(partyA: string, sig: SingleUpnlSigStruct | Promise<SingleUpnlSigStruct> = getDummySingleUpnlSig()) {
		let signature = sig instanceof Promise ? await sig : sig
		await runTx(this.context.liquidationFacet.connect(this.context.signers.liquidator).liquidatePartyB(await this.signer.getAddress(), partyA, signature))
		logger.info(`Hedger::Liquidator: ${partyA}`)
	}

	public async emergencyClosePosition(id: BigNumberish, request: EmergencyCloseRequest = emergencyCloseRequestBuilder().build()) {
		const quote = await this.context.viewFacet.getQuote(id)
		const user = this.context.manager.getUser(quote.partyA)
		logger.detailedDebug(
			serializeToJson({
				request: request,
				hedgerBalanceInfo: await this.getBalanceInfo(quote.partyA),
				hedgerUpnl: await this.getUpnl(quote.partyA),
				userBalanceInfo: await user.getBalanceInfo(),
				userUpnl: await user.getUpnl(),
			})
		)
		await runTx(
			this.context.partyBPositionActionsFacet
				.connect(this.signer)
				.emergencyClosePosition(id, await getDummyPairUpnlAndPriceSig(BigInt(request.price), BigInt(request.upnlPartyA), BigInt(request.upnlPartyB)))
		)
		logger.info(`Hedger::EmergencyClosePosition: ${id}`)
	}

	public async settleUpnl(partyA: string, updatedPrices: bigint[], sig: Promise<SettlementSigStructOutput> | SettlementSigStructOutput = getDummySettlementSig()) {
		let signature = sig instanceof Promise ? await sig : sig

		const user = this.context.manager.getUser(partyA)
		logger.detailedDebug(
			serializeToJson({
				partyA: partyA,
				updatedPrices: updatedPrices,
				sig: sig,
				userBalanceInfo: await user.getBalanceInfo(),
				userUpnl: await user.getUpnl(),
			})
		)
		await runTx(
			this.context.settlementFacet.connect(this.signer).settleUpnl(
				signature,
				updatedPrices,
				partyA
			)
		)
		logger.info(`Hedger::settleUpnl`)
	}

	public async getAddress() {
		return await this.signer.getAddress()
	}

	public async getUpnl(partyA: string): Promise<bigint> {
		let openPositions: QuoteStructOutput[] = []
		const pageSize = 30
		let last = 0
		while (true) {
			const page = await this.context.viewFacet.getPartyBOpenPositions(await this.getAddress(), partyA, last, pageSize)
			openPositions.push(...page)
			if (page.length < pageSize) break
		}

		let upnl = 0n
		for (const pos of openPositions) {
			// Decrypt encrypted quote fields
			const openedPrice = await this.signer.decryptUint256(pos.openedPrice.userCiphertext)
			const quantity = await this.signer.decryptUint256(pos.quantity.userCiphertext)
			const closedAmount = await this.signer.decryptUint256(pos.closedAmount.userCiphertext)
			
			const priceDiff = openedPrice - await getPrice()
			const amount = quantity - closedAmount
			upnl += unDecimal(amount * priceDiff) * (pos.positionType === BigInt(PositionType.LONG) ? -1n : 1n)
		}
		return upnl
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
