import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { decimal, decryptUint256 } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-13: flip trustedObserverAddress then admin-batched re-offboard from primary ciphertext.
 */
export function shouldBehaveLikeAuditM13(): void {
	describe("trusted observer rotation migration", function () {
		it("M-13: after flip+migrate, new observer decrypts allocated/quote; old observer cannot", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const oldObserver = new User(context, context.signers.liquidator)
			await oldObserver.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))

			const newObserver = new User(context, context.signers.user2)
			await newObserver.setup()
			await runTx(context.accountFacet.connect(context.signers.user2).allocate(0))

			await runTx(
				context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.liquidator.address),
			)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			const allocatedBefore = await decryptUint256(
				context,
				await context.viewFacet.observerAllocatedBalanceOfPartyA(partyA),
				context.signers.liquidator,
			)
			expect(allocatedBefore).to.be.greaterThan(0n)

			const observerQuoteBefore = await context.viewFacet.getObserverQuoteValues(quote.quoteId)
			const qtyBefore = await decryptUint256(context, observerQuoteBefore.quantity, context.signers.liquidator)
			expect(qtyBefore).to.be.greaterThan(0n)

			// Flip to new observer — storage still keyed to old until migrate.
			await runTx(
				context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.user2.address),
			)

			const stillReadableByOld = await decryptUint256(
				context,
				await context.viewFacet.observerAllocatedBalanceOfPartyA(partyA),
				context.signers.liquidator,
			)
			expect(stillReadableByOld).to.equal(allocatedBefore)

			await runTx(context.controlFacet.connect(context.signers.admin).migrateObserverForPartyA(partyA, 0, 100))
			await runTx(context.controlFacet.connect(context.signers.admin).migrateObserverForPartyBs([partyB]))

			const allocatedAfter = await decryptUint256(
				context,
				await context.viewFacet.observerAllocatedBalanceOfPartyA(partyA),
				context.signers.user2,
			)
			expect(allocatedAfter).to.equal(allocatedBefore)

			const observerQuoteAfter = await context.viewFacet.getObserverQuoteValues(quote.quoteId)
			const qtyAfter = await decryptUint256(context, observerQuoteAfter.quantity, context.signers.user2)
			expect(qtyAfter).to.equal(qtyBefore)

			const partyBAlloc = await decryptUint256(
				context,
				await context.viewFacet.observerAllocatedBalanceOfPartyB(partyB, partyA),
				context.signers.user2,
			)
			expect(partyBAlloc).to.be.greaterThan(0n)

			await expect(
				context.controlFacet.connect(context.signers.user).migrateObserverForPartyA(partyA, 0, 1),
			).to.be.revertedWith("Accessibility: Must has role")
		})
	})
}
