import "../utils/revertedWith"
import { expect } from "chai"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { emergencyCloseRequestBuilder } from "../models/requestModels/EmergencyCloseRequest"
import { decimal, getQuoteQuantity } from "../utils/Common"
import { getDummySingleUpnlSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-32: emergencyClosePosition requires both parties solvent (PBF:A/B insol).
 * Slim alloc to cva+lf+1 (liq available ignores MM), then adverse mark.
 */
export function shouldBehaveLikeAuditH32(): void {
	describe("emergency close vs insolvency", function () {
		it("H-32: insolvent UPNL blocks emergency close; liquidation still works in PartyB emergency", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			await runTx(context.controlFacet.connect(context.signers.admin as any).setDeallocateDebounceTime(0))

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

			const qty = await getQuoteQuantity(context, quote.quoteId)
			const balA = await user.getBalanceInfo()
			// deallocate uses AvailableForQuote (subtracts MM); leave 1 above total locked.
			const keepA = balA.totalLockedPartyA + decimal(1n)
			const partyAPositions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
			const entryASig = await getDummySingleUpnlSig(
				0n,
				partyAPositions.map((q: any) => BigInt(q.id)),
				partyAPositions.map(() => decimal(1n)),
			)
			await runTx(
				context.accountFacet.connect(context.signers.user).deallocate(balA.allocatedBalances - keepA, entryASig),
			)

			// Liq/emergency available ignores MM: available ≈ 1+mm + upnl. Dump mark → upnl≈-qty < -(1+mm).
			await expect(
				hedger.emergencyClosePosition(quote.quoteId, emergencyCloseRequestBuilder().price(decimal(1n, 15)).build()),
			).to.be.revertedWith("PBF:A insol")

			const balB = await hedger.getBalanceInfo(partyA)
			const keepB = balB.totalLockedPartyB + decimal(1n)
			const partyBPositions = await context.viewFacet.getPartyBOpenPositions(partyB, partyA, 0, 100)
			const entryBSig = await getDummySingleUpnlSig(
				0n,
				partyBPositions.map((q: any) => BigInt(q.id)),
				partyBPositions.map(() => decimal(1n)),
			)
			await runTx(
				context.accountFacet
					.connect(context.signers.hedger)
					.deallocateForPartyB(balB.allocatedBalances - keepB, partyA, entryBSig),
			)

			await expect(
				hedger.emergencyClosePosition(quote.quoteId, emergencyCloseRequestBuilder().price(decimal(10n)).build()),
			).to.be.revertedWith("PBF:B insol")

			const bal = await hedger.getBalanceInfo(partyA)
			// Mark high enough that PartyB UPNL < -(alloc - cva - lf) ≈ -1.
			const markLiq = decimal(10n)
			const partyBUpnl = -((markLiq - decimal(1n)) * qty) / decimal(1n)
			const available = bal.allocatedBalances - bal.lockedCva - bal.lockedLf + partyBUpnl
			expect(available).to.be.lt(0n, `PartyB must be insolvent; available=${available}`)

			const liqSig = await getDummySingleUpnlSig(
				0n,
				partyBPositions.map((q: any) => BigInt(q.id)),
				partyBPositions.map(() => markLiq),
			)
			await runTx(
				context.liquidationFacet.connect(context.signers.liquidator).liquidatePartyB(partyB, partyA, liqSig),
			)

			expect(await context.viewFacet.isPartyBLiquidated(partyB, partyA)).to.equal(true)
		})
	})
}
