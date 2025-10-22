import {expect} from "chai"
import {QuoteStructOutput} from "../../../src/types/contracts/interfaces/ISymmio"
import {getTotalPartyALockedValuesForQuotes, getTotalPartyBLockedValuesForQuotes, unDecimal} from "../../utils/Common"
import {logger} from "../../utils/LoggerUtils"
import {expectToBeApproximately} from "../../utils/SafeMath"
import {PositionType, QuoteStatus} from "../Enums"
import {Hedger} from "../Hedger"
import {RunContext} from "../RunContext"
import {BalanceInfo, User} from "../User"
import {TransactionValidator} from "./TransactionValidator"

export type FillCloseRequestValidatorBeforeArg = {
	user: User
	quoteId: bigint
	hedger: Hedger
}

export type FillCloseRequestValidatorBeforeOutput = {
	balanceInfoPartyA: BalanceInfo
	balanceInfoPartyB: BalanceInfo
	quote: QuoteStructOutput
}

export type FillCloseRequestValidatorAfterArg = {
	user: User
	hedger: Hedger
	quoteId: bigint
	closePrice: bigint
	fillAmount: bigint
	beforeOutput: FillCloseRequestValidatorBeforeOutput
}

export class FillCloseRequestValidator implements TransactionValidator {
	async before(context: RunContext, arg: FillCloseRequestValidatorBeforeArg): Promise<FillCloseRequestValidatorBeforeOutput> {
		logger.debug("Before FillCloseRequestValidator...")
		return {
			balanceInfoPartyA: await arg.user.getBalanceInfo(),
			balanceInfoPartyB: await arg.hedger.getBalanceInfo(await arg.user.getAddress()),
			quote: await context.viewFacet.getQuote(arg.quoteId),
		}
	}

	async after(context: RunContext, arg: FillCloseRequestValidatorAfterArg) {
		logger.debug("After FillCloseRequestValidator...")
// Check Quote
		const newQuote = await context.viewFacet.getQuote(arg.quoteId)
		const oldQuote = arg.beforeOutput.quote
		const decryptedZeroToClose = await arg.user.decryptUint256(newQuote.quantityToClose.userCiphertext)
		const zeroToClose = decryptedZeroToClose === 0n
		const decryptedNewQuantity = await arg.user.decryptUint256(newQuote.quantity.userCiphertext)
		const decryptedNewClosedAmount = await arg.user.decryptUint256(newQuote.closedAmount.userCiphertext)
		const decryptedOldClosedAmount = await arg.user.decryptUint256(oldQuote.closedAmount.userCiphertext)
		const isFullyClosed = decryptedNewQuantity === decryptedNewClosedAmount

		if (isFullyClosed) {
			expect(newQuote.quoteStatus).to.equal(QuoteStatus.CLOSED)
		} else if (zeroToClose || newQuote.quoteStatus === BigInt(QuoteStatus.CANCEL_CLOSE_PENDING)) {
			expect(newQuote.quoteStatus).to.equal(QuoteStatus.OPENED)
		} else {
			expect(newQuote.quoteStatus).to.equal(QuoteStatus.CLOSE_PENDING)
		}

		expect(decryptedNewClosedAmount.toString()).to.equal((decryptedOldClosedAmount + BigInt(arg.fillAmount)).toString())

// TODO: Sometimes fillCloseRequest has Error

		const decryptedNewQuantityToClose = await arg.user.decryptUint256(newQuote.quantityToClose.userCiphertext)
		const decryptedOldQuantityToClose = await arg.user.decryptUint256(oldQuote.quantityToClose.userCiphertext)
		expect(decryptedNewQuantityToClose.toString()).to.equal((decryptedOldQuantityToClose - BigInt(arg.fillAmount)).toString())

		const oldLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes([oldQuote], context.signers.user)
		const newLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes([newQuote], context.signers.user)

		const oldLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes([oldQuote], context.signers.hedger)
		const newLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes([newQuote], context.signers.hedger)

		let profit
		const decryptedOpenedPrice = await arg.user.decryptUint256(newQuote.openedPrice.userCiphertext)
		if (newQuote.positionType === BigInt(PositionType.LONG)) {
			profit = unDecimal((BigInt(arg.closePrice) - decryptedOpenedPrice) * BigInt(arg.fillAmount))
		} else {
			profit = unDecimal((decryptedOpenedPrice - BigInt(arg.closePrice)) * BigInt(arg.fillAmount))
		}

		const decryptedOldQuantity = await arg.user.decryptUint256(oldQuote.quantity.userCiphertext)
		const returnedLockedValuesPartyA = (BigInt(oldLockedValuesPartyA) * BigInt(arg.fillAmount)) / decryptedOldQuantity
		const returnedLockedValuesPartyB = (BigInt(oldLockedValuesPartyB) * BigInt(arg.fillAmount)) / decryptedOldQuantity

// Check Balances partyA
		const newBalanceInfoPartyA = await arg.user.getBalanceInfo()
		const oldBalanceInfoPartyA = arg.beforeOutput.balanceInfoPartyA

		expect(newBalanceInfoPartyA.totalPendingLockedPartyA.toString()).to.equal(oldBalanceInfoPartyA.totalPendingLockedPartyA.toString())
		expectToBeApproximately(BigInt(newBalanceInfoPartyA.totalLockedPartyA), BigInt(oldBalanceInfoPartyA.totalLockedPartyA) - returnedLockedValuesPartyA)
		expectToBeApproximately(BigInt(newBalanceInfoPartyA.allocatedBalances), BigInt(oldBalanceInfoPartyA.allocatedBalances) + profit)

// Check Balances partyB
		const newBalanceInfoPartyB = await arg.hedger.getBalanceInfo(await arg.user.getAddress())
		const oldBalanceInfoPartyB = arg.beforeOutput.balanceInfoPartyB

		expect(newBalanceInfoPartyB.totalPendingLockedPartyB.toString()).to.equal(oldBalanceInfoPartyB.totalPendingLockedPartyB.toString())
		expectToBeApproximately(BigInt(newBalanceInfoPartyB.totalLockedPartyB), BigInt(oldBalanceInfoPartyB.totalLockedPartyB) - returnedLockedValuesPartyB)
		expectToBeApproximately(BigInt(newBalanceInfoPartyB.allocatedBalances), BigInt(oldBalanceInfoPartyB.allocatedBalances) - profit)

	}
}
