import {time} from "@nomicfoundation/hardhat-network-helpers"
import {JsonSerializer} from "typescript-json-serializer"
import {Wallet, ctUint256} from "@coti-io/coti-ethers"
import {ethers} from "hardhat"

import {OrderType, QuoteStatus} from "../models/Enums"
import {RunContext} from "../models/RunContext"
import {safeDiv} from "./SafeMath"
import {network} from "hardhat"
import {QuoteStructOutput, SymbolStructOutput} from "../../src/types/contracts/interfaces/ISymmio"

const defaultSerializer = new JsonSerializer()

export async function decryptUint256(
	context: RunContext,
	ciphertext: ctUint256,
	wallet: Wallet
): Promise<bigint> {
	void context
	return await wallet.decryptUint256(ciphertext)
}

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
	if (
		network.name === "coti-testnet" ||
		network.name === "soda-testnet" ||
		network.name === "private-testnet" ||
		network.name === "localSimCoti"
	) {
		const latestBlock = await ethers.provider.getBlock("latest")
		if (!latestBlock) {
			throw new Error(`Unable to read latest block timestamp on network ${network.name}`)
		}
		return BigInt(latestBlock.timestamp) + 1n + additional
	}
	return 1722859307n
}

export async function getQuoteQuantity(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const quote = await context.viewFacet.getQuote(quoteId);
	// Properly decrypt the encrypted quantity using the user's wallet
	return await decryptUint256(context, quote.quantity.userCiphertext, user);
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
	const quantity = await decryptUint256(context, q.quantity.userCiphertext, user);
	const closedAmount = await decryptUint256(context, q.closedAmount.userCiphertext, user);
	return quantity - closedAmount;
}

export async function getQuoteNotFilledAmount(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	const quantityToClose = await decryptUint256(context, q.quantityToClose.userCiphertext, user);
	const closedAmount = await decryptUint256(context, q.closedAmount.userCiphertext, user);
	return quantityToClose - closedAmount;
}

export async function getQuoteQuantityToClose(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	return await decryptUint256(context, q.quantityToClose.userCiphertext, user);
}

export async function getQuoteRequestedOpenPrice(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	return await decryptUint256(context, q.requestedOpenPrice.userCiphertext, user);
}

export async function getQuoteMarketPrice(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	return await decryptUint256(context, q.marketPrice.userCiphertext, user);
}

export async function getQuoteRequestedClosePrice(context: RunContext, quoteId: bigint, user: Wallet = context.signers.user): Promise<bigint> {
	const q = await context.viewFacet.getQuote(quoteId)
	return await decryptUint256(context, q.requestedClosePrice.userCiphertext, user);
}

export async function getTotalPartyALockedValuesForQuotes(
	context: RunContext,
	quotes: QuoteStructOutput[],
	wallet: Wallet,
	includeMM: boolean = true,
	returnAfterOpened: boolean = true,
): Promise<bigint> {
	let out = 0n
	for (const q of quotes) {
		// Properly decrypt encrypted values using the user's wallet
		const cva = await decryptUint256(context, q.lockedValues.cva.userCiphertext, wallet);
		const lf = await decryptUint256(context, q.lockedValues.lf.userCiphertext, wallet);
		let addition = cva + lf;
		
		if (includeMM) {
			const partyAmm = await decryptUint256(context, q.lockedValues.partyAmm.userCiphertext, wallet);
			addition += partyAmm;
		}
		
		if (returnAfterOpened && q.orderType === BigInt(OrderType.LIMIT)) {
			const requestedOpenPrice = await decryptUint256(context, q.requestedOpenPrice.userCiphertext, wallet);
			const openedPrice = await decryptUint256(context, q.openedPrice.userCiphertext, wallet);
			if (requestedOpenPrice < openedPrice) {
				addition = addition * openedPrice / requestedOpenPrice;
			}
		}
		out += addition
	}
	return out
}

export async function getTotalPartyBLockedValuesForQuotes(
	context: RunContext,
	quotes: QuoteStructOutput[],
	wallet: Wallet,
	includeMM: boolean = true,
	returnAfterOpened: boolean = true,
): Promise<bigint> {
	let out = 0n
	for (const q of quotes) {
		// Properly decrypt encrypted values using the user's wallet
		const cva = await decryptUint256(context, q.lockedValues.cva.userCiphertext, wallet);
		const lf = await decryptUint256(context, q.lockedValues.lf.userCiphertext, wallet);
		let addition = cva + lf;
		
		if (includeMM) {
			const partyBmm = await decryptUint256(context, q.lockedValues.partyBmm.userCiphertext, wallet);
			addition += partyBmm;
		}
		
		if (returnAfterOpened && q.orderType === BigInt(OrderType.LIMIT)) {
			const requestedOpenPrice = await decryptUint256(context, q.requestedOpenPrice.userCiphertext, wallet);
			const openedPrice = await decryptUint256(context, q.openedPrice.userCiphertext, wallet);
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
	wallet: Wallet = context.signers.user,
	includeMM: boolean = true,
	returnAfterOpened: boolean = true,
): Promise<bigint> {
	let quotes: QuoteStructOutput[] = []
	for (const quoteId of quoteIds) quotes.push(await context.viewFacet.getQuote(quoteId))
	return getTotalPartyALockedValuesForQuotes(context, quotes, wallet, includeMM, returnAfterOpened)
}

export async function getTradingFeeForQuotes(context: RunContext, quoteIds: bigint[], wallet: Wallet = context.signers.user): Promise<bigint> {
	let out = 0n
	for (const quoteId of quoteIds) {
		let q = await context.viewFacet.getQuote(quoteId)
		let tf = (await context.viewFacet.getSymbol(q.symbolId)).tradingFee
		
		const quantity = await decryptUint256(context, q.quantity.userCiphertext, wallet);
		
		if (q.orderType === BigInt(OrderType.LIMIT)) {
			const requestedOpenPrice = await decryptUint256(context, q.requestedOpenPrice.userCiphertext, wallet);
			out += unDecimal(quantity * requestedOpenPrice * tf, 36)
		} else {
			const marketPrice = await decryptUint256(context, q.marketPrice.userCiphertext, wallet);
			out += unDecimal(quantity * marketPrice * tf, 36)
		}
	}
	return out
}

export async function getTradingFeeForQuoteWithFilledAmount(context: RunContext, quoteId: bigint, filledAmounts: bigint, wallet: Wallet = context.signers.user): Promise<bigint> {
	let out = 0n
	let q = await context.viewFacet.getQuote(quoteId)
	let tf = (await context.viewFacet.getSymbol(q.symbolId)).tradingFee
	
	if (q.orderType === BigInt(OrderType.LIMIT)) {
		const requestedOpenPrice = await decryptUint256(context, q.requestedOpenPrice.userCiphertext, wallet);
		out += unDecimal(filledAmounts * requestedOpenPrice * tf, 36)
	} else {
		const marketPrice = await decryptUint256(context, q.marketPrice.userCiphertext, wallet);
		out += unDecimal(filledAmounts * marketPrice * tf, 36)
	}
	return out
}

export async function pausePartyB(context: RunContext): Promise<void> {
	await context.controlFacet.connect(context.signers.admin as any).pausePartyBActions()
}

export async function pausePartyA(context: RunContext): Promise<void> {
	await context.controlFacet.connect(context.signers.admin as any).pausePartyAActions()
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
	const filledAmount = await decryptUint256(context, encryptedValues.filledAmount, context.signers.user)
	const openedPrice = await decryptUint256(context, encryptedValues.openedPrice, context.signers.user)
	
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
