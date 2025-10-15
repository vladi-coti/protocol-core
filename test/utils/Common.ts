import {time} from "@nomicfoundation/hardhat-network-helpers"
import {JsonSerializer} from "typescript-json-serializer"
import {ctUint256, Wallet} from "@coti-io/coti-ethers"

import {OrderType, QuoteStatus} from "../models/Enums"
import {RunContext} from "../models/RunContext"
import {safeDiv} from "./SafeMath"
import {network} from "hardhat"
import {QuoteStructOutput, SymbolStructOutput} from "../../src/types/contracts/interfaces/ISymmio"
import {User} from "../models/User"

const defaultSerializer = new JsonSerializer()

export type PromiseOrValue<T> = T | Promise<T>;

export function decimal(value: bigint, decimal: number = 18): bigint {
	return value * 10n ** BigInt(decimal)
}

export function unDecimal(value: bigint, decimal: number = 18): bigint {
	return value / 10n ** BigInt(decimal)
}

export async function getBlockTimestamp(additional: bigint = 0n): Promise<bigint> {
	if (network.name === "hardhat") {
		return BigInt(await time.latest()) + 1n + additional
	}
	if (network.name === "coti-testnet" || network.name === "soda-testnet") {
		return BigInt(Math.floor(Date.now() / 1000)) + 1n + additional
	}
	return 1722859307n
}

export async function getQuoteQuantity(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const quote = await context.viewFacet.getQuote(quoteId);
	// Properly decrypt the encrypted quantity using the user's wallet
	return await user.decryptUint256(quote.quantity.userCiphertext);
}

export async function getQuoteMinLeftQuantityForClose(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const openAmount = await getQuoteOpenAmount(context, quoteId, user)
	const totalLocked = await getTotalLockedValuesForQuoteIds(context, [quoteId], user)

	const q = await context.viewFacet.getQuote(quoteId)
	const symbol: SymbolStructOutput = await context.viewFacet.getSymbol(q.symbolId)

	return safeDiv(symbol.minAcceptableQuoteValue * openAmount, totalLocked)
}

export async function getQuoteMinLeftQuantityForFill(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const openAmount = await getQuoteOpenAmount(context, quoteId, user)
	const totalLocked = await getTotalLockedValuesForQuoteIds(context, [quoteId], user)

	const q = await context.viewFacet.getQuote(quoteId)
	const symbol: SymbolStructOutput = await context.viewFacet.getSymbol(q.symbolId)

	return safeDiv(symbol.minAcceptableQuoteValue * openAmount, totalLocked)
}

export async function getQuoteOpenAmount(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	const quantity = await user.decryptUint256(q.quantity.userCiphertext);
	const closedAmount = await user.decryptUint256(q.closedAmount.userCiphertext);
	return quantity - closedAmount;
}

export async function getQuoteNotFilledAmount(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	const quantityToClose = await user.decryptUint256(q.quantityToClose.userCiphertext);
	const closedAmount = await user.decryptUint256(q.closedAmount.userCiphertext);
	return quantityToClose - closedAmount;
}

export async function getTotalPartyALockedValuesForQuotes(
	quotes: QuoteStructOutput[],
	user: Wallet,
	includeMM: boolean = true,
	returnAfterOpened: boolean = true,
): Promise<bigint> {
	let out = 0n
	for (const q of quotes) {
		// Properly decrypt encrypted values using the user's wallet
		const cva = await user.decryptUint256(q.lockedValues.cva.userCiphertext);
		const lf = await user.decryptUint256(q.lockedValues.lf.userCiphertext);
		let addition = cva + lf;
		
		if (includeMM) {
			const partyAmm = await user.decryptUint256(q.lockedValues.partyAmm.userCiphertext);
			addition += partyAmm;
		}
		
		if (returnAfterOpened && q.orderType === BigInt(OrderType.LIMIT)) {
			const requestedOpenPrice = await user.decryptUint256(q.requestedOpenPrice.userCiphertext);
			const openedPrice = await user.decryptUint256(q.openedPrice.userCiphertext);
			if (requestedOpenPrice < openedPrice) {
				addition = addition * openedPrice / requestedOpenPrice;
			}
		}
		out += addition
	}
	return out
}

export async function getTotalPartyBLockedValuesForQuotes(
	quotes: QuoteStructOutput[],
	user: User,
	includeMM: boolean = true,
	returnAfterOpened: boolean = true,
): Promise<bigint> {
	let out = 0n
	for (const q of quotes) {
		// Properly decrypt encrypted values using the user's wallet
		const cva = await user.decryptUint256(q.lockedValues.cva.userCiphertext);
		const lf = await user.decryptUint256(q.lockedValues.lf.userCiphertext);
		let addition = cva + lf;
		
		if (includeMM) {
			const partyBmm = await user.decryptUint256(q.lockedValues.partyBmm.userCiphertext);
			addition += partyBmm;
		}
		
		if (returnAfterOpened && q.orderType === BigInt(OrderType.LIMIT)) {
			const requestedOpenPrice = await user.decryptUint256(q.requestedOpenPrice.userCiphertext);
			const openedPrice = await user.decryptUint256(q.openedPrice.userCiphertext);
			if (requestedOpenPrice < openedPrice) {
				addition = addition * openedPrice / requestedOpenPrice;
			}
		}
		out += addition
	}
	return out
}

export async function getTotalLockedValuesForQuoteIds(
	context: RunContext,
	quoteIds: bigint[],
	user: Wallet,
	includeMM: boolean = true,
	returnAfterOpened: boolean = true,
): Promise<bigint> {
	let quotes: QuoteStructOutput[] = []
	for (const quoteId of quoteIds) quotes.push(await context.viewFacet.getQuote(quoteId))
	return getTotalPartyALockedValuesForQuotes(quotes, user, includeMM, returnAfterOpened)
}

export async function getTradingFeeForQuotes(context: RunContext, quoteIds: bigint[], user: Wallet = context.signers.user): Promise<bigint> {
	let out = 0n
	for (const quoteId of quoteIds) {
		let q = await context.viewFacet.getQuote(quoteId)
		let tf = (await context.viewFacet.getSymbol(q.symbolId)).tradingFee
		
		const quantity = await user.decryptUint256(q.quantity.userCiphertext);
		
		if (q.orderType === BigInt(OrderType.LIMIT)) {
			const requestedOpenPrice = await user.decryptUint256(q.requestedOpenPrice.userCiphertext);
			out += unDecimal(quantity * requestedOpenPrice * tf, 36)
		} else {
			const marketPrice = await user.decryptUint256(q.marketPrice.userCiphertext);
			out += unDecimal(quantity * marketPrice * tf, 36)
		}
	}
	return out
}

export async function getTradingFeeForQuoteWithFilledAmount(context: RunContext, quoteId: bigint, filledAmounts: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	let out = 0n
	let q = await context.viewFacet.getQuote(quoteId)
	let tf = (await context.viewFacet.getSymbol(q.symbolId)).tradingFee
	
	if (q.orderType === BigInt(OrderType.LIMIT)) {
		const requestedOpenPrice = await user.decryptUint256(q.requestedOpenPrice.userCiphertext);
		out += unDecimal(filledAmounts * requestedOpenPrice * tf, 36)
	} else {
		const marketPrice = await user.decryptUint256(q.marketPrice.userCiphertext);
		out += unDecimal(filledAmounts * marketPrice * tf, 36)
	}
	return out
}

export async function pausePartyB(context: RunContext): Promise<void> {
	await context.controlFacet.connect(context.signers.admin).pausePartyBActions()
}

export async function pausePartyA(context: RunContext): Promise<void> {
	await context.controlFacet.connect(context.signers.admin).pausePartyAActions()
}

export async function getValue<T>(pov: T | Promise<T>): Promise<T> {
	if (pov instanceof Promise) return await pov
	return pov
}

export async function getBigNumberValue(pov: bigint | Promise<bigint>): Promise<bigint> {
	if (pov instanceof Promise) return await pov
	return pov
}

export async function getSymbols(context: RunContext): Promise<SymbolStructOutput[]> {
	return await context.viewFacet.getSymbols(0, 100)
}

export function max(a: bigint, b: bigint): bigint {
	return a >= b ? a : b
}

export function min(a: bigint, b: bigint): bigint {
	return a >= b ? b : a
}

export function serializeToJson(object: any): any {
	return defaultSerializer.serialize(object)
}

export async function checkStatus(context: RunContext, quoteId: bigint, quoteStatus: QuoteStatus): Promise<boolean> {
	return (await context.viewFacet.getQuote(quoteId)).quoteStatus === BigInt(quoteStatus)
}

export function getPriceFetcher(symbolIds: bigint[], prices: bigint[]): (symbolId: bigint) => Promise<bigint> {
	return async (symbolId: bigint): Promise<bigint> => {
		for (let i = 0; i < symbolIds.length; i++) {
			if (symbolIds[i] === symbolId) return prices[i]
		}
		throw new Error("Invalid price requested")
	}
}

/**
 * Helper function to decrypt encrypted position values from OpenPositionForPartyA/PartyB events
 * @param context The run context
 * @param encryptedValues The encrypted position values from the event
 * @param userAddress The address of the user whose encryption key to use
 * @returns Decrypted filledAmount and openedPrice
 */
export async function decryptPositionValues(
	context: RunContext,
	encryptedValues: { filledAmount: any; openedPrice: any },
	userAddress: string
): Promise<{ filledAmount: bigint; openedPrice: bigint }> {
	// Get the user to decrypt the values
	const user = context.manager.getUser(userAddress)
	const filledAmount = await user.decryptUint256(encryptedValues.filledAmount)
	const openedPrice = await user.decryptUint256(encryptedValues.openedPrice)
	
	return { filledAmount, openedPrice }
}

/**
 * Helper function to extract and decrypt position data from OpenPositionForPartyA event
 * @param context The run context
 * @param eventData The event data from OpenPositionForPartyA
 * @returns Decrypted position data
 */
export async function getDecryptedPositionDataFromPartyAEvent(
	context: RunContext,
	eventData: any
): Promise<{ filledAmount: bigint; openedPrice: bigint; quoteId: bigint; partyA: string; partyB: string }> {
	const decryptedValues = await decryptPositionValues(context, eventData.values, eventData.partyA)
	return {
		...decryptedValues,
		quoteId: eventData.quoteId,
		partyA: eventData.partyA,
		partyB: eventData.partyB
	}
}

/**
 * Helper function to extract and decrypt position data from OpenPositionForPartyB event
 * @param context The run context
 * @param eventData The event data from OpenPositionForPartyB
 * @returns Decrypted position data
 */
export async function getDecryptedPositionDataFromPartyBEvent(
	context: RunContext,
	eventData: any
): Promise<{ filledAmount: bigint; openedPrice: bigint; quoteId: bigint; partyA: string; partyB: string }> {
	const decryptedValues = await decryptPositionValues(context, eventData.values, eventData.partyB)
	return {
		...decryptedValues,
		quoteId: eventData.quoteId,
		partyA: eventData.partyA,
		partyB: eventData.partyB
	}
}
