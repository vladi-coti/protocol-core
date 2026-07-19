import {setBalance} from "@nomicfoundation/hardhat-network-helpers"
import {BigNumberish, ethers, EventLog} from "ethers"

import {decryptUint256, decimal, serializeToJson, unDecimal} from "../utils/Common"
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
import {ctUint256, Wallet} from "@coti-io/coti-ethers"
import {
	PairUpnlAndPriceSigStruct,
	PrivateClosePositionParamsStruct,
	PrivateOpenPositionParamsStruct,
	QuoteStructOutput,
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

	public async decryptUint256(ciphertext: ctUint256): Promise<bigint> {
		return await decryptUint256(this.context, ciphertext, this.signer)
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
		await runTx(this.context.accountManagementFacet.connect(this.signer).depositToReserveVault(amount, await this.signer.getAddress()))
	}

	public async withdrawFromReserveVault(amount: BigNumberish) {
		await runTx(this.context.accountManagementFacet.connect(this.signer).withdrawFromReserveVault(amount))
	}

	public async balanceOfReserveVault(): Promise<bigint> {
		return await decryptUint256(
			this.context,
			await this.context.viewFacet.connect(this.signer).balanceOfReserveVault(await this.signer.getAddress()),
			this.signer,
		)
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

	public async lockQuote(quoteData: QuoteData, upnl: bigint = 0n, allocateCoefficient: bigint | null = decimal(12n, 17)) {
		const { quoteId: id } = quoteData
		if (allocateCoefficient != null) {
			const quote = await this.context.viewFacet.getQuote(id)
			const partyA = quote.partyA
			const user = this.context.manager.getUser(partyA)
			const price = await decryptUint256(this.context, quote.requestedOpenPrice.userCiphertext, user.getWallet())
			const quantity = await decryptUint256(this.context, quote.quantity.userCiphertext, user.getWallet())
			const notional = unDecimal(quantity * price)
			await runTx(
				this.context.accountFacet.connect(this.signer).allocateForPartyB(unDecimal(notional * BigInt(allocateCoefficient)), partyA)
			)
		}
		const quote = await this.context.viewFacet.getQuote(id)
		await runTx(this.context.partyBQuoteActionsFacet.connect(this.signer).lockQuote(id, await this.buildSinglePriceSig(quote.partyA, await this.getAddress())))

		logger.info(`Hedger::LockQuote: ${id}`)
	}

	public async unlockQuote(id: BigNumberish) {
		await runTx(this.context.partyBQuoteActionsFacet.connect(this.signer).unlockQuote(id))
		logger.info(`Hedger::UnLockQuote: ${id}`)
	}

	public async lockAndOpenQuote(quoteData: QuoteData, allocateCoefficient: bigint | null = decimal(12n, 17), openRequest: OpenRequest = limitOpenRequestBuilder().build()) {
		const { quoteId: id } = quoteData
		if (allocateCoefficient != null) {
			const quote = await this.context.viewFacet.getQuote(id)
			const partyA = quote.partyA
			const user = this.context.manager.getUser(partyA)
			const price = await decryptUint256(this.context, quote.requestedOpenPrice.userCiphertext, user.getWallet())
			const quantity = await decryptUint256(this.context, quote.quantity.userCiphertext, user.getWallet())
			const notional = unDecimal(quantity * price)
			await runTx(
				this.context.accountFacet.connect(this.signer).allocateForPartyB(unDecimal(notional * BigInt(allocateCoefficient)), partyA)
			)
		}
		const quote = await this.context.viewFacet.getQuote(id)
		const {encryptedParams, upnlSig} = await this.buildOpenPositionCalldataArgs(
			openRequest,
			this.context.partyBGroupActionsFacet.interface.getFunction("lockAndOpenQuote").selector,
			id,
			quote.partyA,
		)
		await runTx(
			this.context.partyBGroupActionsFacet.connect(this.signer).lockAndOpenQuote(
				id,
				encryptedParams,
				await this.buildSinglePriceSig(quote.partyA),
				upnlSig,
			)
		)
	}

	public async buildOpenPositionCalldataArgs(
		request: OpenRequest,
		selector: string = this.context.partyBPositionActionsFacet.interface.getFunction("openPosition").selector,
		quoteId?: BigNumberish,
		partyA?: string,
	): Promise<{
		encryptedParams: PrivateOpenPositionParamsStruct
		upnlSig: PairUpnlAndPriceSigStruct
	}> {
		const contractAddress = this.context.diamond

		const encryptedFilledAmount = await this.signer.encryptUint256(BigInt(request.filledAmount), contractAddress, selector)
		const encryptedOpenedPrice = await this.signer.encryptUint256(BigInt(request.openPrice), contractAddress, selector)

		const upnlSig = await getDummyPairUpnlAndPriceSig(BigInt(request.price), BigInt(request.upnlPartyA), BigInt(request.upnlPartyB))
		if (quoteId !== undefined && partyA !== undefined) {
			await this.populatePairPriceSig(upnlSig as any, partyA, BigInt(request.price), BigInt(quoteId.toString()))
		}

		return {
			encryptedParams: {
				encryptedFilledAmount,
				encryptedOpenedPrice,
			},
			upnlSig,
		}
	}

	public async openPosition({quoteId: id}: QuoteData, request: OpenRequest = limitOpenRequestBuilder().build()) {
		const quote = await this.context.viewFacet.getQuote(id)
		
		const partyA = quote.partyA
		const user = this.context.manager.getUser(partyA)

		const hedgerBalanceInfo = await this.getBalanceInfo(partyA)
		const userBalanceInfo = await user.getBalanceInfo()
		
		logger.detailedDebug(
			serializeToJson({
				request: request,
				hedgerBalanceInfo: hedgerBalanceInfo,
				hedgerUpnl: await this.getUpnl(partyA),
				userBalanceInfo: userBalanceInfo,
				userUpnl: await user.getUpnl(),
			})
		)

		const {encryptedParams, upnlSig} = await this.buildOpenPositionCalldataArgs(request, undefined, id, partyA)
		
		const tx = await runTx(
			this.context.partyBPositionActionsFacet
				.connect(this.signer)
				.openPosition(
					id,
					encryptedParams,
					upnlSig
				)
		)
		logger.info(`Hedger::OpenPosition: ${id} gas used: ${tx.gasUsed.toString()}`)
	}

	public async getBalance(): Promise<bigint> {
		return await this.context.viewFacet.balanceOf(await this.getAddress())
	}

	public async getBalanceInfo(partyA: string): Promise<BalanceInfo> {
		const result = await this.context.viewFacet.balanceInfoOfPartyB(this.signer.address, partyA)
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

	public async acceptCancelRequest(id: BigNumberish) {
		await runTx(this.context.partyBQuoteActionsFacet.connect(this.signer).acceptCancelRequest(id))
		logger.info(`Hedger::AcceptCancelRequest: ${id}`)
	}

	public async buildFillCloseRequestCalldataArgs(
		request: FillCloseRequest,
		selector: string = this.context.partyBCloseActionsFacet.interface.getFunction("fillCloseRequest").selector,
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
		await this.populatePairPriceSig(upnlSig as any, quote.partyA, BigInt(request.price))
		
		const tx = await this.context.partyBCloseActionsFacet
				.connect(this.signer)
				.fillCloseRequest(
					id,
					encryptedParams,
					upnlSig
				)

		const receipt = await tx.wait()
		if (!receipt) {
			throw new Error("FillCloseRequest failed")
		}
		
		logger.info(`Hedger::FillCloseRequest: ${id}, gas used: ${receipt.gasUsed.toString()}`)
	}

	public async chargeFundingRate(partyA: string, quoteIds: BigNumberish[], rates: BigNumberish[], signature: PairUpnlSigStructOutput) {
		await this.context.fundingRateFacet.connect(this.signer).chargeFundingRate(partyA, quoteIds, rates, signature)
		logger.info(`Hedger::ChargeFundingRate: ${partyA}, ${quoteIds}, ${rates}`)
	}

	public async acceptCancelCloseRequest(id: BigNumberish) {
		await runTx(this.context.partyBCloseActionsFacet.connect(this.signer).acceptCancelCloseRequest(id))
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
			this.context.recoveryActionsFacet
				.connect(this.signer)
				.emergencyClosePosition(id, await this.buildPairPriceSig(quote.partyA, BigInt(request.price)))
		)
		logger.info(`Hedger::EmergencyClosePosition: ${id}`)
	}

	private async openedMarkPrices(positions: QuoteStructOutput[]): Promise<bigint[]> {
		const partyAWallet = this.context.signers.user
		return Promise.all(positions.map(async quote => decryptUint256(this.context, quote.openedPrice.userCiphertext, partyAWallet)))
	}

	private async buildSinglePriceSig(partyA: string, partyB?: string): Promise<SingleUpnlSigStruct> {
		const positions = partyB
			? await this.context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
			: await this.context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
		const sig = await getDummySingleUpnlSig()
		;(sig as any).quoteIds = positions.map((quote: any) => BigInt(quote.id))
		;(sig as any).prices = await this.openedMarkPrices(positions)
		return sig
	}

	private async buildPairPriceSig(partyA: string, price: bigint): Promise<PairUpnlAndPriceSigStruct> {
		const sig = await getDummyPairUpnlAndPriceSig(price)
		const partyAPositions = await this.context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
		const partyBPositions = await this.context.viewFacet.getPartyBOpenPositions(await this.getAddress(), partyA, 0, 100)
		// Apply the mark to the full open book (emergency / solvency paths); do not use entry prices.
		sig.partyAQuoteIds = partyAPositions.map((quote: any) => BigInt(quote.id))
		sig.partyAPrices = partyAPositions.map(() => price)
		sig.partyBQuoteIds = partyBPositions.map((quote: any) => BigInt(quote.id))
		sig.partyBPrices = partyBPositions.map(() => price)
		return sig
	}

	private async populatePairPriceSig(sig: any, partyA: string, price: bigint, extraQuoteId?: bigint) {
		const partyAPositions = await this.context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
		const partyBPositions = await this.context.viewFacet.getPartyBOpenPositions(await this.getAddress(), partyA, 0, 100)
		sig.partyAQuoteIds = partyAPositions.map((quote: any) => BigInt(quote.id))
		sig.partyAPrices = await this.openedMarkPrices(partyAPositions)
		sig.partyBQuoteIds = partyBPositions.map((quote: any) => BigInt(quote.id))
		sig.partyBPrices = await this.openedMarkPrices(partyBPositions)
		if (extraQuoteId !== undefined) {
			sig.partyAQuoteIds.push(extraQuoteId)
			sig.partyAPrices.push(price)
			sig.partyBQuoteIds.push(extraQuoteId)
			sig.partyBPrices.push(price)
		}
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
			const user = this.context.manager.getUser(pos.partyA)

			// Decrypt encrypted quote fields
			const openedPrice = await decryptUint256(this.context, pos.openedPrice.userCiphertext, user.getWallet())
			const quantity = await decryptUint256(this.context, pos.quantity.userCiphertext, user.getWallet())
			const closedAmount = await decryptUint256(this.context, pos.closedAmount.userCiphertext, user.getWallet())
			
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
