import "../utils/revertedWith"
import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { emergencyCloseRequestBuilder } from "../models/requestModels/EmergencyCloseRequest"
import { decimal } from "../utils/Common"
import { getDummySingleUpnlSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-32: emergencyClosePosition requires both parties solvent (PBF:A/B insol),
 * then LibQuote.closeQuote also rejects negative post-PnL balances.
 *
 * Auditor claim: recovery is blocked exactly when a party is insolvent.
 * Product reality: insolvency is the liquidation path; emergency close is an
 * orderly solvent unwind under emergency / symbol invalid. Liquidation is not
 * gated by emergencyMode / partyBEmergencyStatus.
 */
export function shouldBehaveLikeAuditH32(): void {
	describe("emergency close vs insolvency", function () {
		it("H-32: insolvent UPNL blocks emergency close; liquidation still works in PartyB emergency", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(4000n), decimal(4000n))

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			await runTx(context.controlFacet.setPartyBEmergencyStatus([partyB], true))

			await expect(
				hedger.emergencyClosePosition(quote.quoteId, emergencyCloseRequestBuilder().upnlPartyA(decimal(-575n)).build()),
			).to.be.revertedWith("PBF:A insol")

			await expect(
				hedger.emergencyClosePosition(quote.quoteId, emergencyCloseRequestBuilder().upnlPartyB(decimal(-410n)).build()),
			).to.be.revertedWith("PBF:B insol")

			const bal = await hedger.getBalanceInfo(partyA)
			// available ≈ alloc - cva - lf + upnl; need available < 0 while emergency is on.
			const upnl = -(bal.allocatedBalances - bal.lockedCva - bal.lockedLf + 1n)
			const available = bal.allocatedBalances - bal.lockedCva - bal.lockedLf + upnl
			expect(available).to.be.lt(0n, `PartyB must be insolvent for liq path; available=${available}`)

			await runTx(
				context.liquidationFacet
					.connect(context.signers.liquidator)
					.liquidatePartyB(partyB, partyA, await getDummySingleUpnlSig(upnl)),
			)

			expect(await context.viewFacet.isPartyBLiquidated(partyB, partyA)).to.equal(true)
		})
	})
}
