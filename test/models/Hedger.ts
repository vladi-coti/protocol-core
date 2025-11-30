import {setBalance} from "@nomicfoundation/hardhat-network-helpers"
import {BigNumberish, ethers, EventLog} from "ethers"

import {decimal, fetchPartyBEventFromQuote, serializeToJson, unDecimal} from "../utils/Common"
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

	public async decryptQuoteData(partyBEvent: SendQuoteForPartyBEvent.OutputObject): Promise<{quantity: bigint, price: bigint, partyA: string}> {
		const { values } = partyBEvent
		const { price, quantity } = values
		const quantityDecrypted = await this.signer.decryptUint256(quantity)
		const priceDecrypted = await this.signer.decryptUint256(price)
		return { quantity: quantityDecrypted, price: priceDecrypted, partyA: partyBEvent.partyA }
	}

	public async lockQuote(quoteData: QuoteData, upnl: bigint = 0n, allocateCoefficient: bigint | null = decimal(12n, 17)) {
		const { quoteId: id } = quoteData
		let partyBEvent = quoteData.partyBEvent

		if (allocateCoefficient != null) {
			// If partyBEvent is undefined, try to fetch it from the contract
			if (partyBEvent == undefined) {
				partyBEvent = await fetchPartyBEventFromQuote(this.context, id, this.signer)
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
		let partyBEvent: SendQuoteForPartyBEvent.OutputObject | undefined
		
		if ('partyBEvent' in quoteData && quoteData.partyBEvent) {
			partyA = quoteData.partyBEvent.partyA
			partyBEvent = quoteData.partyBEvent
		} else if ('partyA' in quoteData) {
			partyA = quoteData.partyA
			// Fetch PartyB event if not provided
			partyBEvent = await fetchPartyBEventFromQuote(this.context, quoteData.quoteId, this.signer)
		} else {
			throw new Error("PartyA is required - provide either partyBEvent or partyA directly")
		}
		const user = this.context.manager.getUser(partyA)
		
		// Pre-flight checks before attempting openPosition
		const quote = await this.context.viewFacet.getQuote(quoteData.quoteId)
		const hedgerBalanceInfo = await this.getBalanceInfo(partyA)
		const userBalanceInfo = await user.getBalanceInfo()
		const hedgerUpnl = await this.getUpnl(partyA)
		const userUpnl = await user.getUpnl()
		const currentBlock = await this.signer.provider?.getBlock("latest")
		const currentTimestamp = currentBlock ? BigInt(currentBlock.timestamp) : 0n
		
		// Get quote details for validation - use PartyB event data which hedger can decrypt
		const { quantity: quoteQuantity, price: quoteRequestedOpenPrice } = await this.decryptQuoteData(partyBEvent)
		const quoteMarketPrice = await this.signer.decryptUint256(partyBEvent.values.marketPrice)
		
		console.log(`Hedger::openPosition - quoteId: ${quoteData.quoteId}`)
		console.log(`Hedger::openPosition - quoteStatus: ${quote.quoteStatus}`)
		console.log(`Hedger::openPosition - orderType: ${quote.orderType} (0=MARKET, 1=LIMIT)`)
		console.log(`Hedger::openPosition - positionType: ${quote.positionType} (0=LONG, 1=SHORT)`)
		console.log(`Hedger::openPosition - deadline: ${quote.deadline}, currentTimestamp: ${currentTimestamp}`)
		console.log(`Hedger::openPosition - quoteQuantity: ${quoteQuantity.toString()}`)
		console.log(`Hedger::openPosition - quoteRequestedOpenPrice: ${quoteRequestedOpenPrice.toString()}`)
		console.log(`Hedger::openPosition - quoteMarketPrice: ${quoteMarketPrice.toString()}`)
		console.log(`Hedger::openPosition - filledAmount: ${request.filledAmount.toString()}`)
		console.log(`Hedger::openPosition - openPrice: ${request.openPrice.toString()}`)
		console.log(`Hedger::openPosition - price (market): ${request.price.toString()}`)
		console.log(`Hedger::openPosition - partyAUpnl: ${request.upnlPartyA.toString()}`)
		console.log(`Hedger::openPosition - partyBUpnl: ${request.upnlPartyB.toString()}`)
		console.log(`Hedger::openPosition - hedgerAllocatedBalances: ${hedgerBalanceInfo.allocatedBalances.toString()}`)
		console.log(`Hedger::openPosition - hedgerTotalLockedPartyB: ${hedgerBalanceInfo.totalLockedPartyB.toString()}`)
		console.log(`Hedger::openPosition - userAllocatedBalances: ${userBalanceInfo.allocatedBalances.toString()}`)
		console.log(`Hedger::openPosition - userTotalLockedPartyA: ${userBalanceInfo.totalLockedPartyA.toString()}`)
		
		// Validation checks
		const openPriceBigInt = BigInt(request.openPrice.toString())
		const filledAmountBigInt = BigInt(request.filledAmount.toString())
		if (quote.orderType == 1n) { // LIMIT
			if (quote.positionType == 0n) { // LONG
				if (openPriceBigInt > quoteRequestedOpenPrice) {
					console.log(`Hedger::openPosition - WARNING: LONG LIMIT - openPrice (${openPriceBigInt}) > requestedOpenPrice (${quoteRequestedOpenPrice})`)
				}
			} else { // SHORT
				if (openPriceBigInt < quoteRequestedOpenPrice) {
					console.log(`Hedger::openPosition - WARNING: SHORT LIMIT - openPrice (${openPriceBigInt}) < requestedOpenPrice (${quoteRequestedOpenPrice})`)
				}
			}
			if (filledAmountBigInt > quoteQuantity || filledAmountBigInt == 0n) {
				console.log(`Hedger::openPosition - WARNING: LIMIT - filledAmount (${filledAmountBigInt}) invalid for quantity (${quoteQuantity})`)
			}
		} else { // MARKET
			if (filledAmountBigInt != quoteQuantity) {
				console.log(`Hedger::openPosition - WARNING: MARKET - filledAmount (${filledAmountBigInt}) != quantity (${quoteQuantity})`)
			}
		}
		
		logger.detailedDebug(
			serializeToJson({
				request: request,
				hedgerBalanceInfo: hedgerBalanceInfo,
				hedgerUpnl: hedgerUpnl,
				userBalanceInfo: userBalanceInfo,
				userUpnl: userUpnl,
			})
		)
		
		const {encryptedParams, upnlSig} = await this.buildOpenPositionCalldataArgs(request)
		
		try {
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
		} catch (error: any) {
			console.log(`Hedger::openPosition - ERROR: ${error.message}`)
			console.log(`Hedger::openPosition - Error code: ${error.code}`)
			throw error
		}
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
		const maxReasonableValue = decimal(1000000n, 18) // 1M tokens max
		const minInt256 = -(2n ** 255n)
		const maxInt256 = 2n ** 255n - 1n
		
		for (const pos of openPositions) {
			try {
				// Decrypt encrypted quote fields
				const openedPrice = await this.signer.decryptUint256(pos.openedPrice.userCiphertext)
				const quantity = await this.signer.decryptUint256(pos.quantity.userCiphertext)
				const closedAmount = await this.signer.decryptUint256(pos.closedAmount.userCiphertext)
				
				// Validate decrypted values are reasonable (not garbage from uninitialized/corrupted data)
				if (quantity > maxReasonableValue || openedPrice > maxReasonableValue || closedAmount > maxReasonableValue) {
					console.log(`Hedger::getUpnl - Skipping position ${pos.id}: Invalid decrypted values (quantity: ${quantity}, openedPrice: ${openedPrice}, closedAmount: ${closedAmount})`)
					continue
				}
				
				if (closedAmount > quantity) {
					console.log(`Hedger::getUpnl - Skipping position ${pos.id}: closedAmount (${closedAmount}) > quantity (${quantity})`)
					continue
				}
				
				const currentPrice = await getPrice()
				const priceDiff = openedPrice - currentPrice
				const amount = quantity - closedAmount
				
				// Calculate UPNL: original formula with bounds checking
				let positionUpnl = unDecimal(amount * priceDiff) * (pos.positionType === BigInt(PositionType.LONG) ? -1n : 1n)
				
				// Clamp to int256 bounds to prevent overflow
				if (positionUpnl < minInt256) {
					console.log(`Hedger::getUpnl - Clamping position ${pos.id} UPNL from ${positionUpnl} to ${minInt256}`)
					positionUpnl = minInt256
				} else if (positionUpnl > maxInt256) {
					console.log(`Hedger::getUpnl - Clamping position ${pos.id} UPNL from ${positionUpnl} to ${maxInt256}`)
					positionUpnl = maxInt256
				}
				
				upnl += positionUpnl
			} catch (error: any) {
				console.log(`Hedger::getUpnl - Error processing position ${pos.id}: ${error.message}`)
				// Skip this position if decryption fails
				continue
			}
		}
		
		// Final bounds check
		if (upnl < minInt256) upnl = minInt256
		if (upnl > maxInt256) upnl = maxInt256
		
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
