import {expect} from "chai"

import {QuoteStructOutput} from "../../../src/types/contracts/interfaces/ISymmio"
import {decryptUint256, getTotalPartyALockedValuesForQuotes, getTotalPartyBLockedValuesForQuotes, unDecimal} from "../../utils/Common"
import {logger} from "../../utils/LoggerUtils"
import {expectToBeApproximately} from "../../utils/SafeMath"
import {PositionType, QuoteStatus} from "../Enums"
import {Hedger} from "../Hedger"
import {RunContext} from "../RunContext"
import {BalanceInfo, User} from "../User"
import {TransactionValidator} from "./TransactionValidator"

export type EmergencyCloseRequestValidatorBeforeArg = {
	user: User
	quoteId: bigint
	hedger: Hedger
}

export type EmergencyCloseRequestValidatorBeforeOutput = {
	balanceInfoPartyA: BalanceInfo
	balanceInfoPartyB: BalanceInfo
	quote: QuoteStructOutput
}

export type EmergencyCloseRequestValidatorAfterArg = {
	user: User
	hedger: Hedger
	quoteId: bigint
	price: bigint
	beforeOutput: EmergencyCloseRequestValidatorBeforeOutput
}

export class EmergencyCloseRequestValidator implements TransactionValidator {
	async before(context: RunContext, arg: EmergencyCloseRequestValidatorBeforeArg): Promise<EmergencyCloseRequestValidatorBeforeOutput> {
		logger.debug("Before EmergencyCloseRequestValidator...")
		return {
			balanceInfoPartyA: await arg.user.getBalanceInfo(),
			balanceInfoPartyB: await arg.hedger.getBalanceInfo(await arg.user.getAddress()),
			quote: await context.viewFacet.getQuote(arg.quoteId),
		}
	}

	async after(context: RunContext, arg: EmergencyCloseRequestValidatorAfterArg) {
		logger.debug("After EmergencyCloseRequestValidator...")
		// Check Quote
		const newQuote = await context.viewFacet.getQuote(arg.quoteId)
		const oldQuote = arg.beforeOutput.quote

		expect(newQuote.quoteStatus).to.be.equal(QuoteStatus.CLOSED)
		const decryptedNewClosedAmount = await decryptUint256(context, newQuote.closedAmount.userCiphertext, arg.user.getWallet())
		const decryptedOldQuantity = await decryptUint256(context, oldQuote.quantity.userCiphertext, arg.user.getWallet())
		const decryptedOldClosedAmount = await decryptUint256(context, oldQuote.closedAmount.userCiphertext, arg.user.getWallet())
		const decryptedNewOpenedPrice = await decryptUint256(context, newQuote.openedPrice.userCiphertext, arg.user.getWallet())
		expect(decryptedNewClosedAmount).to.be.equal(decryptedOldQuantity)

		const oldLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes(context, [oldQuote], context.signers.user)
		const newLockedValuesPartyA = await getTotalPartyALockedValuesForQuotes(context, [newQuote], context.signers.user)

		const oldLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes(context, [oldQuote], context.signers.hedger)
		const newLockedValuesPartyB = await getTotalPartyBLockedValuesForQuotes(context, [newQuote], context.signers.hedger)

		const closedAmount = BigInt(decryptedNewClosedAmount) - BigInt(decryptedOldClosedAmount)
		let profit
		if (newQuote.positionType === BigInt(PositionType.LONG)) {
			profit = unDecimal((BigInt(arg.price) - BigInt(decryptedNewOpenedPrice)) * closedAmount)
		} else {
			profit = unDecimal((BigInt(decryptedNewOpenedPrice) - BigInt(arg.price)) * closedAmount)
		}

		const returnedLockedValuesPartyA = (BigInt(oldLockedValuesPartyA) * closedAmount) / BigInt(decryptedOldQuantity)
		const returnedLockedValuesPartyB = (BigInt(oldLockedValuesPartyB) * closedAmount) / BigInt(decryptedOldQuantity)

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
