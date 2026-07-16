import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType, QuoteStatus } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyHighLowPriceSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible, timeCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-04: force-close decrypts private close-price predicates before Muon auth.
 *
 * Attack (even with junk sig): probe public high/low against encrypted
 * requestedClosePrice — early "Requested close price not reached" vs later
 * failure/success oracles whether the private threshold was crossed.
 *
 * Production fix: verifyHighLowPrice before any onboard/decrypt of that price.
 * (Audit Muon-off still no-ops verify; source-order check locks the fix.)
 */
export function shouldBehaveLikeAuditH04(): void {
	describe("force-close price predicate before Muon verify", function () {
		it("H-04: public price probes oracle encrypted requestedClosePrice via revert", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(4000n), decimal(4000n))

			// Warm-up + SHORT to close (same pattern as ForceClosePosition.behavior)
			const long = await user.sendQuote()
			await hedger.lockQuote(long)
			await hedger.openPosition(long)

			const short = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await hedger.lockQuote(short)
			await hedger.openPosition(short)

			const closePrice = decimal(1n)
			await user.requestToClosePosition(
				short.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, short.quoteId))
					.closePrice(closePrice)
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			await runTx(context.controlFacet.setForceCloseMinSigPeriod(10))
			const quote = await context.viewFacet.getQuote(short.quoteId)
			const gapRatio = decimal(1n, 17) // 10%
			await runTx(context.controlFacet.setForceCloseGapRatio(quote.symbolId, gapRatio))
			await runTx(context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress))

			const now = await getBlockTimestamp()
			const cooldowns = await context.viewFacet.forceCloseCooldowns()
			const startTime = cooldowns[0] + now
			const endTime = cooldowns[0] + now + 10n
			await timeCompatible.increase(cooldowns[0] + 10n + cooldowns[1] + 1n)

			// SHORT: maximum = requestedClose * (1 - gap). lowest must be <= maximum.
			const maxClose = closePrice - (closePrice * gapRatio) / decimal(1n)

			await expect(
				user.forceClosePosition(
					short.quoteId,
					await getDummyHighLowPriceSig(
						startTime,
						endTime,
						maxClose + 1n, // lowest too high → private predicate fails before Muon
						decimal(10n),
						decimal(1n),
						decimal(1n),
						0n,
						0n,
						0n,
					),
				),
			).to.be.revertedWith("PartyAFacet: Requested close price not reached")

			// Same junk Muon fields, lowest low enough → predicate passes (Muon audit-off is no-op).
			// Observable difference vs prior revert = oracle over encrypted requestedClosePrice.
			await user.forceClosePosition(
				short.quoteId,
				await getDummyHighLowPriceSig(startTime, endTime, 0n, decimal(10n), decimal(1n), decimal(1n), 0n, 0n, 0n),
			)
			expect((await context.viewFacet.getQuote(short.quoteId)).quoteStatus).to.equal(QuoteStatus.CLOSED)
		})

		it("H-04: verifyHighLowPrice must run before requestedClosePrice onboard", function () {
			const srcPath = path.join(__dirname, "../../contracts/facets/ForceActions/ForceActionsFacetImpl.sol")
			const src = fs.readFileSync(srcPath, "utf8")
			const start = src.indexOf("function forceClosePosition(")
			expect(start).to.be.gte(0)
			const body = src.slice(start, src.indexOf("\n\tfunction ", start + 1) === -1 ? src.length : src.indexOf("\n\tfunction ", start + 1))
			const verifyAt = body.indexOf("LibMuonForceActions.verifyHighLowPrice")
			const onboardAt = body.indexOf("requestedClosePrice.ciphertext")
			expect(verifyAt, "missing verifyHighLowPrice").to.be.gte(0)
			expect(onboardAt, "missing requestedClosePrice onboard").to.be.gte(0)
			expect(verifyAt).to.be.lessThan(
				onboardAt,
				"H-04: Muon verify must precede private close-price onboard/decrypt",
			)
		})
	})
}
