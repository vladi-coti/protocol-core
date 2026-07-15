import "../utils/revertedWith"
import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { getDummySingleUpnlSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-15: remainingLf can exceed PartyB allocated when insolvent with +UPNL.
 *
 * Reach lf > alloc by deallocateForPartyB under a large dummy +UPNL (solves
 * "Will be liquidatable"), then liquidatePartyB with mild +UPNL = cva+1 which
 * keeps deficit < lf so remainingLf = alloc+1 > alloc → checkedSub reverts.
 */
export function shouldBehaveLikeAuditH15(): void {
	describe("PartyB liquidation LF exceed allocated", function () {
		it("H-15: insolvent PartyB with +UPNL must not revert on remainingLf > alloc", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(20000n), decimal(10000n), decimal(8000n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(20000n), decimal(20000n))

			const partyA = await user.getAddress()

			// Sim warm-up (H-12/H-14).
			const warm = await user.sendQuote()
			await hedger.lockQuote(warm)
			await hedger.openPosition(warm)

			const lfQuote = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.cva(decimal(10n))
					.partyAmm(decimal(10n))
					.partyBmm(decimal(10n))
					.lf(decimal(200n))
					.quantity(decimal(50n))
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(280n), partyA))
			await hedger.lockQuote(lfQuote, 0n, null)
			await hedger.openPosition(lfQuote, limitOpenRequestBuilder().filledAmount(decimal(50n)).build())

			const before = await hedger.getBalanceInfo(partyA)
			expect(before.lockedLf).to.be.gt(0n)

			// Leave alloc just under lockedLf (inflated UPNL so deallocate still passes).
			const targetAlloc = before.lockedLf - decimal(1n)
			expect(before.allocatedBalances).to.be.gt(targetAlloc, "need excess alloc to pull down")
			const pull = before.allocatedBalances - targetAlloc
			await runTx(
				context.accountFacet
					.connect(context.signers.hedger)
					.deallocateForPartyB(pull, partyA, await getDummySingleUpnlSig(decimal(100000n))),
			)

			const bal = await hedger.getBalanceInfo(partyA)
			expect(bal.lockedLf).to.be.gt(bal.allocatedBalances, `lf>alloc; lf=${bal.lockedLf} alloc=${bal.allocatedBalances}`)

			const upnl = bal.lockedCva + 1n
			const available = bal.allocatedBalances - bal.lockedCva - bal.lockedLf + upnl
			expect(available).to.be.lt(0n, `must be insolvent; available=${available}`)

			const hedgerAddress = await hedger.getAddress()

			await runTx(
				context.liquidationFacet
					.connect(context.signers.liquidator)
					.liquidatePartyB(hedgerAddress, partyA, await getDummySingleUpnlSig(upnl)),
			)

			const after = await hedger.getBalanceInfo(partyA)
			expect(after.allocatedBalances).to.equal(0n)
			expect(await context.viewFacet.isPartyBLiquidated(hedgerAddress, partyA)).to.equal(true)
		})
	})
}
