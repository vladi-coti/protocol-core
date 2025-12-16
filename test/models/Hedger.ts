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

	public async lockQuote(quoteData: QuoteData, upnl: bigint = 0n, allocateCoefficient: bigint | null = decimal(12n, 17)) {
		const { quoteId: id } = quoteData
		if (allocateCoefficient != null) {
			const quote = await this.context.viewFacet.getQuote(id)
			const partyA = quote.partyA
			const user = this.context.manager.getUser(partyA)
			const price = await decryptUint256(this.context, quote.requestedOpenPrice.userCiphertext, user.getWallet())
			const quantity = await decryptUint256(this.context, quote.quantity.userCiphertext, user.getWallet())
			console.log("Hedger::LockQuote: price: ", price)
			console.log("Hedger::LockQuote: quantity: ", quantity)
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
			const quote = await this.context.viewFacet.getQuote(id)
			const partyA = quote.partyA
			const user = this.context.manager.getUser(partyA)
			const price = await decryptUint256(this.context, quote.requestedOpenPrice.userCiphertext, user.getWallet())
			const quantity = await decryptUint256(this.context, quote.quantity.userCiphertext, user.getWallet())
			console.log("Hedger::LockAndOpenQuote: price: ", price)
			console.log("Hedger::LockAndOpenQuote: quantity: ", quantity)
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

	public async openPosition({quoteId: id}: QuoteData, request: OpenRequest = limitOpenRequestBuilder().build()) {
		const quote = await this.context.viewFacet.getQuote(id)
		
		const partyA = quote.partyA
		const user = this.context.manager.getUser(partyA)

		console.log("Hedger::OpenPosition: request: ", request)
		
		// Pre-flight validation checks
		const symbol = await this.context.viewFacet.getSymbol(quote.symbolId)
		const requestedOpenPrice = await decryptUint256(this.context, quote.requestedOpenPrice.userCiphertext, user.getWallet())
		const quantity = await decryptUint256(this.context, quote.quantity.userCiphertext, user.getWallet())
		const openPrice = BigInt(request.openPrice.toString())
		const filledAmount = BigInt(request.filledAmount.toString())
		
		// Get locked values from pending balances (before opening)
		const hedgerBalanceInfo = await this.getBalanceInfo(partyA)
		const userBalanceInfo = await user.getBalanceInfo()
		const hedgerUpnl = await this.getUpnl(partyA)
		const userUpnl = await user.getUpnl()
		const marketPrice = BigInt(request.price.toString())
		
		// Calculate what the scaled locked values will be after opening
		const priceScale = openPrice * 10n**18n / requestedOpenPrice
		const totalPendingLockedPartyA = userBalanceInfo.totalPendingLockedPartyA
		const scaledTotalForPartyA = (totalPendingLockedPartyA * priceScale) / 10n**18n
		
		// Calculate leverage: (quantity * openedPrice) / totalForPartyA
		// Contract comment says "is in 18 decimals", meaning the result is in 18 decimals
		// Since quantity and openedPrice are already in 18 decimals, and totalForPartyA is in base units,
		// the result is: (quantity * openedPrice) / totalForPartyA (already in 18 decimals)
		const leverage = (filledAmount * openPrice) / scaledTotalForPartyA
		
		// Calculate solvency check (happens AFTER position is opened)
		// The solvency check uses locked balances AFTER opening, so we need to account for the new locked values
		// Get locked values for THIS quote from the quote itself (encrypted for PartyA, so use user's wallet)
		const quoteCva = await decryptUint256(this.context, quote.lockedValues.cva.userCiphertext, user.getWallet())
		const quoteLf = await decryptUint256(this.context, quote.lockedValues.lf.userCiphertext, user.getWallet())
		
		// Scale the locked values by price scale
		const scaledQuoteCva = (quoteCva * priceScale) / 10n**18n
		const scaledQuoteLf = (quoteLf * priceScale) / 10n**18n
		
		// After opening, the new locked balances are: current locked + scaled quote locked values
		// The solvency check uses only CVA+LF (not MM) for available balance calculation
		// Note: The quote's values are currently in pendingLockedBalances, and will be:
		// 1. Removed from pendingLockedBalances (unscaled)
		// 2. Added to lockedBalances (scaled)
		const currentLockedCvaLfPartyA = userBalanceInfo.lockedCva + userBalanceInfo.lockedLf
		const currentLockedCvaLfPartyB = hedgerBalanceInfo.lockedCva + hedgerBalanceInfo.lockedLf
		const newLockedCvaLfPartyA = currentLockedCvaLfPartyA + scaledQuoteCva + scaledQuoteLf
		const newLockedCvaLfPartyB = currentLockedCvaLfPartyB + scaledQuoteCva + scaledQuoteLf
		
		// Calculate PnL adjustment: filledAmount * (openedPrice - marketPrice) / 1e18
		// The contract uses: gtDiff = gtFilledAmount.mul(gtOpenedPrice.sub(gtMarketPrice)).div(gtScaleFactor)
		// Calculate the actual signed difference directly (the contract converts uint256 to int256 using two's complement)
		const priceDiffSigned = openPrice >= marketPrice 
			? (openPrice - marketPrice)  // Positive difference
			: -(marketPrice - openPrice) // Negative difference (simulating uint256 underflow -> int256 conversion)
		const diffSigned = (filledAmount * priceDiffSigned) / 10n**18n
		
		// Calculate available balances after opening (for solvency check)
		// PartyA: available = (allocated - cvaLf) + upnl + adjustment
		// PartyB: available = (allocated - cvaLf) + upnl + adjustment
		const partyAFreeBalance = userBalanceInfo.allocatedBalances - newLockedCvaLfPartyA
		const partyBFreeBalance = hedgerBalanceInfo.allocatedBalances - newLockedCvaLfPartyB
		
		let partyAAvailableAfter: bigint
		let partyBAvailableAfter: bigint
		
		// Apply PnL adjustment based on position type (matching on-chain logic)
		// The contract uses: gtPartyAAdjustment and gtPartyBAdjustment based on position type and price comparison
		const openedPriceGteMarket = openPrice >= marketPrice
		const isLong = quote.positionType === BigInt(PositionType.LONG)
		
		let partyAAdjustment: bigint
		let partyBAdjustment: bigint
		
		if (isLong) {
			// LONG position
			if (openedPriceGteMarket) {
				// PartyA loses, PartyB gains
				partyAAdjustment = -diffSigned
				partyBAdjustment = diffSigned
			} else {
				// PartyA gains, PartyB loses
				partyAAdjustment = diffSigned
				partyBAdjustment = -diffSigned
			}
		} else {
			// SHORT position
			if (openedPriceGteMarket) {
				// PartyA gains, PartyB loses
				partyAAdjustment = diffSigned
				partyBAdjustment = -diffSigned
			} else {
				// PartyA loses, PartyB gains
				partyAAdjustment = -diffSigned
				partyBAdjustment = diffSigned
			}
		}
		
		partyAAvailableAfter = partyAFreeBalance + userUpnl + partyAAdjustment
		partyBAvailableAfter = partyBFreeBalance + hedgerUpnl + partyBAdjustment
		
		console.log("Hedger::OpenPosition: quoteId: ", id)
		console.log("Hedger::OpenPosition: orderType: ", quote.orderType, " (0=LIMIT, 1=MARKET)")
		console.log("Hedger::OpenPosition: positionType: ", quote.positionType, " (0=LONG, 1=SHORT)")
		console.log("Hedger::OpenPosition: requestedOpenPrice: ", requestedOpenPrice)
		console.log("Hedger::OpenPosition: openPrice (being sent): ", openPrice)
		console.log("Hedger::OpenPosition: marketPrice: ", marketPrice)
		console.log("Hedger::OpenPosition: quantity: ", quantity)
		console.log("Hedger::OpenPosition: filledAmount: ", filledAmount)
		console.log("Hedger::OpenPosition: priceScale: ", priceScale, " (openedPrice/requestedOpenPrice)")
		console.log("Hedger::OpenPosition: totalPendingLockedPartyA (unscaled): ", totalPendingLockedPartyA)
		console.log("Hedger::OpenPosition: scaledTotalForPartyA: ", scaledTotalForPartyA)
		console.log("Hedger::OpenPosition: minAcceptableQuoteValue: ", symbol.minAcceptableQuoteValue)
		console.log("Hedger::OpenPosition: leverage: ", leverage)
		console.log("Hedger::OpenPosition: maxLeverage: ", symbol.maxLeverage)
		console.log("Hedger::OpenPosition: SOLVENCY CHECK:")
		console.log("Hedger::OpenPosition:   Quote CVA (unscaled): ", quoteCva, ", LF (unscaled): ", quoteLf)
		console.log("Hedger::OpenPosition:   Quote CVA (scaled): ", scaledQuoteCva, ", LF (scaled): ", scaledQuoteLf)
		console.log("Hedger::OpenPosition:   PartyA: currentLockedCvaLf=", currentLockedCvaLfPartyA, ", newLockedCvaLf=", newLockedCvaLfPartyA)
		console.log("Hedger::OpenPosition:   PartyA: allocated=", userBalanceInfo.allocatedBalances, ", freeBalance=", partyAFreeBalance)
		console.log("Hedger::OpenPosition:   PartyA: currentUpnl=", userUpnl, ", partyAAdjustment=", partyAAdjustment, " (diffSigned=", diffSigned, ", openedPriceGteMarket=", openedPriceGteMarket, "), availableAfter=", partyAAvailableAfter)
		console.log("Hedger::OpenPosition:   PartyB: currentLockedCvaLf=", currentLockedCvaLfPartyB, ", newLockedCvaLf=", newLockedCvaLfPartyB)
		console.log("Hedger::OpenPosition:   PartyB: allocated=", hedgerBalanceInfo.allocatedBalances, ", freeBalance=", partyBFreeBalance)
		console.log("Hedger::OpenPosition:   PartyB: currentUpnl=", hedgerUpnl, ", partyBAdjustment=", partyBAdjustment, " (diffSigned=", diffSigned, ", openedPriceGteMarket=", openedPriceGteMarket, "), availableAfter=", partyBAvailableAfter)
		
		if (scaledTotalForPartyA < symbol.minAcceptableQuoteValue) {
			console.log("Hedger::OpenPosition: WARNING - scaledTotalForPartyA < minAcceptableQuoteValue - will revert!")
		}
		if (leverage > symbol.maxLeverage) {
			console.log("Hedger::OpenPosition: WARNING - leverage > maxLeverage - will revert!")
		}
		if (partyAAvailableAfter < 0n) {
			console.log("Hedger::OpenPosition: WARNING - PartyA availableBalance < 0 - will revert!")
		}
		if (partyBAvailableAfter < 0n) {
			console.log("Hedger::OpenPosition: WARNING - PartyB availableBalance < 0 - will revert!")
		}
		
		logger.detailedDebug(
			serializeToJson({
				request: request,
				hedgerBalanceInfo: hedgerBalanceInfo,
				hedgerUpnl: await this.getUpnl(partyA),
				userBalanceInfo: userBalanceInfo,
				userUpnl: await user.getUpnl(),
			})
		)

		const {encryptedParams, upnlSig} = await this.buildOpenPositionCalldataArgs(request)
		
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
