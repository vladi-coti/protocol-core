import {expect} from "chai"
import {ViewQuoteStructOutput} from "../../../src/types/contracts/interfaces/ISymmio"
import {decryptUint256, getTotalPartyALockedValuesForQuotes, getTotalPartyBLockedValuesForQuotes, unDecimal} from "../../utils/Common"
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
	quote: ViewQuoteStructOutput
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
		const decryptedZeroToClose = await decryptUint256(context, newQuote.quantityToClose, arg.user.getWallet())
		const zeroToClose = decryptedZeroToClose === 0n
		const decryptedNewQuantity = await decryptUint256(context, newQuote.quantity, arg.user.getWallet())
		const decryptedNewClosedAmount = await decryptUint256(context, newQuote.closedAmount, arg.user.getWallet())
		const decryptedOldClosedAmount = await decryptUint256(context, oldQuote.closedAmount, arg.user.getWallet())
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

		const decryptedNewQuantityToClose = await decryptUint256(context, newQuote.quantityToClose, arg.user.getWallet())
		const decryptedOldQuantityToClose = await decryptUint256(context, oldQuote.quantityToClose, arg.user.getWallet())
		expect(decryptedNewQuantityToClose.toString()).to.equal((decryptedOldQuantityToClose - BigInt(arg.fillAmount)).toString())

		const oldLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes(context, [oldQuote], context.signers.user)
		const newLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes(context, [newQuote], context.signers.user)

		const oldLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes(context, [oldQuote], context.signers.hedger)
		const newLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes(context, [newQuote], context.signers.hedger)

		let profit
		const decryptedOpenedPrice = await decryptUint256(context, newQuote.openedPrice, arg.user.getWallet())
		if (newQuote.positionType === BigInt(PositionType.LONG)) {
			profit = unDecimal((BigInt(arg.closePrice) - decryptedOpenedPrice) * BigInt(arg.fillAmount))
		} else {
			profit = unDecimal((decryptedOpenedPrice - BigInt(arg.closePrice)) * BigInt(arg.fillAmount))
		}

		const decryptedOldQuantity = await decryptUint256(context, oldQuote.quantity, arg.user.getWallet())
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
