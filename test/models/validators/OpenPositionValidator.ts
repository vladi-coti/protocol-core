import {BigNumber as BN} from "bignumber.js"
import {expect} from "chai"

import {QuoteStructOutput} from "../../../src/types/contracts/interfaces/ISymmio"
import {
	decryptUint256,
	getTotalPartyALockedValuesForQuotes,
	getTotalPartyBLockedValuesForQuotes,
	getTradingFeeForQuotes,
	getTradingFeeForQuoteWithFilledAmount
} from "../../utils/Common"
import {logger} from "../../utils/LoggerUtils"
import {expectToBeApproximately} from "../../utils/SafeMath"
import {QuoteStatus} from "../Enums"
import {Hedger} from "../Hedger"
import {RunContext} from "../RunContext"
import {BalanceInfo, User} from "../User"
import {TransactionValidator} from "./TransactionValidator"

export type OpenPositionValidatorBeforeArg = {
	user: User
	quoteId: bigint
	hedger: Hedger
}

export type OpenPositionValidatorBeforeOutput = {
	balanceInfoPartyA: BalanceInfo
	balanceInfoPartyB: BalanceInfo
	quote: QuoteStructOutput
	feeCollectorBalance: bigint
	feeCollector: string
}

export type OpenPositionValidatorAfterArg = {
	user: User
	hedger: Hedger
	quoteId: bigint
	openedPrice: bigint
	fillAmount: bigint
	beforeOutput: OpenPositionValidatorBeforeOutput
	newQuoteId?: bigint
	newQuoteTargetStatus?: QuoteStatus
}

export class OpenPositionValidator implements TransactionValidator {
	private async getEffectiveFeeCollector(context: RunContext, affiliate: string): Promise<string> {
		const affiliateFeeCollector = await context.viewFacet.getFeeCollector(affiliate)
		return affiliateFeeCollector === "0x0000000000000000000000000000000000000000"
			? await context.viewFacet.getDefaultFeeCollector()
			: affiliateFeeCollector
	}

	private async decryptFeeCollectorBalance(context: RunContext, feeCollector: string): Promise<bigint> {
		const encryptedBalance = await context.viewFacet.feeCollectorBalance(feeCollector)
		if (encryptedBalance.ciphertextHigh === 0n && encryptedBalance.ciphertextLow === 0n) {
			return 0n
		}
		const signer = Object.values(context.signers).find((value: any) => value?.address === feeCollector) as any
		if (!signer) {
			throw new Error(`No test signer found for fee collector ${feeCollector}`)
		}
		return decryptUint256(context, encryptedBalance, signer)
	}

	async before(context: RunContext, arg: OpenPositionValidatorBeforeArg): Promise<OpenPositionValidatorBeforeOutput> {
		logger.debug("Before OpenPositionValidator...")
		const quote = await context.viewFacet.getQuote(arg.quoteId)
		const feeCollector = await this.getEffectiveFeeCollector(context, quote.affiliate)
		return {
			balanceInfoPartyA: await arg.user.getBalanceInfo(),
			balanceInfoPartyB: await arg.hedger.getBalanceInfo(await arg.user.getAddress()),
			quote: quote,
			feeCollectorBalance: await this.decryptFeeCollectorBalance(context, feeCollector),
			feeCollector,
		}
	}

	async after(context: RunContext, arg: OpenPositionValidatorAfterArg) {
		logger.debug("After OpenPositionValidator...")
		// Check Quote
		const newQuote = await context.viewFacet.getQuote(arg.quoteId)
		const newOpenedPrice = await decryptUint256(context, newQuote.openedPrice.userCiphertext, arg.user.getWallet())
		const newQuantity = await decryptUint256(context, newQuote.quantity.userCiphertext, arg.user.getWallet())
		const oldQuote = arg.beforeOutput.quote
		const oldRequestedOpenPrice = await decryptUint256(context, oldQuote.requestedOpenPrice.userCiphertext, arg.user.getWallet())
		const oldQuantity = await decryptUint256(context, oldQuote.quantity.userCiphertext, arg.user.getWallet())
		expect(newQuote.quoteStatus).to.be.equal(QuoteStatus.OPENED)
		expect(newOpenedPrice).to.be.equal(arg.openedPrice)
		expect(newQuantity).to.be.equal(arg.fillAmount)

		const feeCollector = await this.getEffectiveFeeCollector(context, newQuote.affiliate)
		expect(feeCollector).to.equal(arg.beforeOutput.feeCollector)
		const newCollectorBalance = await this.decryptFeeCollectorBalance(context, feeCollector)
		const expectedTradingFee = await getTradingFeeForQuoteWithFilledAmount(context, newQuote.id!, arg.fillAmount)
		const balanceChange = newCollectorBalance - arg.beforeOutput.feeCollectorBalance
		expect(balanceChange).to.be.equal(expectedTradingFee)

		const oldLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes(context, [oldQuote], arg.user.getWallet())
		const newLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes(context, [newQuote], arg.user.getWallet())

		const oldLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes(context, [oldQuote], arg.user.getWallet())
		const newLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes(context, [newQuote], arg.user.getWallet())

		const fillAmountCoef = new BN(arg.fillAmount.toString()).div(new BN(oldQuantity.toString()))
		const priceCoef = new BN(arg.openedPrice.toString()).div(new BN(oldRequestedOpenPrice.toString()))
		const partially = !fillAmountCoef.eq(1)

		if (partially && arg.newQuoteId != null) {
			const newlyCreatedQuote = await context.viewFacet.getQuote(arg.newQuoteId!)
			const newlyCreatedQuantity = await decryptUint256(context, newlyCreatedQuote.quantity.userCiphertext, arg.user.getWallet())
			expect(newlyCreatedQuote.quoteStatus).to.be.equal(arg.newQuoteTargetStatus!)
			const lv = await getTotalPartyALockedValuesForQuotes(context, [newlyCreatedQuote], arg.user.getWallet())
			expect(newlyCreatedQuantity).to.be.equal(oldQuantity - arg.fillAmount)
			expect(lv).to.be.equal(new BN(oldLockedValuesPartyA.toString()).times(new BN(1).minus(fillAmountCoef)).toString())
		}

		const partialLockedValues = BigInt(new BN(oldLockedValuesPartyA.toString()).times(fillAmountCoef).toFixed(0, BN.ROUND_DOWN).toString())
		const partialWithPriceLockedValuesPartyA = BigInt(
			new BN(oldLockedValuesPartyA.toString()).times(fillAmountCoef).times(priceCoef).toFixed(0, BN.ROUND_DOWN).toString(),
		)
		const partialWithPriceLockedValuesPartyB = BigInt(
			new BN(oldLockedValuesPartyB.toString()).times(fillAmountCoef).times(priceCoef).toFixed(0, BN.ROUND_DOWN).toString(),
		)
		expectToBeApproximately(newLockedValuesPartyA, partialWithPriceLockedValuesPartyA)

		// Check Balances partyA
		const newBalanceInfoPartyA = await arg.user.getBalanceInfo()
		const oldBalanceInfoPartyA = arg.beforeOutput.balanceInfoPartyA
		if (oldQuote.quoteStatus == BigInt(QuoteStatus.CANCEL_PENDING)) {
			expect(newBalanceInfoPartyA.totalPendingLockedPartyA).to.be.equal(
				(oldBalanceInfoPartyA.totalPendingLockedPartyA - oldLockedValuesPartyA).toString(),
			)
		} else {
			expectToBeApproximately(newBalanceInfoPartyA.totalPendingLockedPartyA, oldBalanceInfoPartyA.totalPendingLockedPartyA - partialLockedValues)
		}
		expectToBeApproximately(newBalanceInfoPartyA.totalLockedPartyA, oldBalanceInfoPartyA.totalLockedPartyA + partialWithPriceLockedValuesPartyA)
		if (arg.newQuoteTargetStatus == QuoteStatus.CANCELED) {
			expect(newBalanceInfoPartyA.allocatedBalances).to.be.equal(
				(oldBalanceInfoPartyA.allocatedBalances + (await getTradingFeeForQuotes(context, [arg.newQuoteId!]))).toString(),
			)
		} else {
			expect(newBalanceInfoPartyA.allocatedBalances).to.be.equal(oldBalanceInfoPartyA.allocatedBalances.toString())
		}

		// Check Balances partyB
		const newBalanceInfoPartyB = await arg.hedger.getBalanceInfo(await arg.user.getAddress())
		const oldBalanceInfoPartyB = arg.beforeOutput.balanceInfoPartyB

		if (arg.newQuoteTargetStatus == QuoteStatus.CANCELED) {
			expect(newBalanceInfoPartyB.totalPendingLockedPartyB).to.be.equal(
				(oldBalanceInfoPartyB.totalPendingLockedPartyB - oldLockedValuesPartyB).toString(),
			)
		} else {
			expectToBeApproximately(newBalanceInfoPartyB.totalPendingLockedPartyB, oldBalanceInfoPartyB.totalPendingLockedPartyB - oldLockedValuesPartyB)
		}
		expectToBeApproximately(newBalanceInfoPartyB.totalLockedPartyB, oldBalanceInfoPartyB.totalLockedPartyB + partialWithPriceLockedValuesPartyB)
		expect(newBalanceInfoPartyB.allocatedBalances).to.be.equal(oldBalanceInfoPartyB.allocatedBalances.toString())
	}
}
