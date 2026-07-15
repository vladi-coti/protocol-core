import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { getDummyHighLowPriceSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible, timeCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-14: force-close PartyB liquidation path credits reserve into allocated, then
 * calls liquidatePartyBFromAvailable with the *pre-reserve* available balance.
 * Correct input is available+reserve (still negative when reserve only partially covers).
 *
 * Red signal: with tiny partial reserve R, PartyA recovery must be strictly less than
 * (no-reserve recovery + R) when D > LF > D-R. The bug overpays ≈ R.
 */
export function shouldBehaveLikeAuditH14(): void {
	describe("force-close liquidation stale deficit after reserve credit", function () {
		async function prepareForceCloseInsolventShort(reserve: bigint) {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(4000n), decimal(4000n))

			// Mirror ForceClosePosition.behavior: open LONG then SHORT (sim onboarding / account wiring).
			const long = await user.sendQuote()
			await hedger.lockQuote(long)
			await hedger.openPosition(long)

			const short = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.quantity(decimal(75n))
					.build(),
			)
			await hedger.lockQuote(short)
			await hedger.openPosition(short, limitOpenRequestBuilder().filledAmount(decimal(75n)).build())

			await user.requestToClosePosition(
				short.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(await getQuoteQuantity(context, short.quoteId))
					.closePrice(decimal(1n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			await runTx(context.controlFacet.setForceCloseMinSigPeriod(10))
			const quote = await context.viewFacet.getQuote(short.quoteId)
			await runTx(context.controlFacet.setForceCloseGapRatio(quote.symbolId, decimal(1n, 17)))
			await runTx(context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(ethers.ZeroAddress))

			if (reserve > 0n) {
				await hedger.depositToReserveVault(reserve)
			}

			const now = await getBlockTimestamp()
			const cooldowns = await context.viewFacet.forceCloseCooldowns()
			const startTime = cooldowns[0] + now
			const endTime = cooldowns[0] + now + 10n
			await timeCompatible.increase(cooldowns[0] + 10n + cooldowns[1] + 1n)

			const hedgerBefore = await hedger.getBalanceInfo(await user.getAddress())
			const partyABefore = (await user.getBalanceInfo()).allocatedBalances

			const highLowSig = await getDummyHighLowPriceSig(
				startTime,
				endTime,
				0n,
				decimal(10n),
				decimal(35n, 17), // 3.5 — between solvent@3 and deep insolvent@5/7
				decimal(35n, 17),
				0n,
				0n,
				0n,
			)
			await user.forceClosePosition(short.quoteId, highLowSig)

			const partyAAfter = (await user.getBalanceInfo()).allocatedBalances
			const liquidated = await context.viewFacet.isPartyBLiquidated(await hedger.getAddress(), await user.getAddress())
			const reserveLeft = await hedger.balanceOfReserveVault()
			const quoteAfter = await context.viewFacet.getQuote(short.quoteId)

			return {
				partyAGain: partyAAfter - partyABefore,
				liquidated,
				reserveLeft,
				quoteStatus: quoteAfter.quoteStatus,
				lockedLf: hedgerBefore.lockedLf,
				allocatedPartyB: hedgerBefore.allocatedBalances,
			}
		}

		it("H-14: partial reserve must shrink deficit used for PartyA recovery", async function () {
			// lf≈6e18 on this book. Use mild insolvency so D is a bit above lf, then R small enough
			// that D-R < lf (remainingLf > 0 only when deficit input includes reserve credit).
			const reserve = decimal(2n)

			const none = await prepareForceCloseInsolventShort(0n)
			expect(none.liquidated, `baseline must liquidate; gain=${none.partyAGain} lf=${none.lockedLf}`).to.equal(true)

			const partial = await prepareForceCloseInsolventShort(reserve)
			expect(partial.liquidated, `partial must liquidate; gain=${partial.partyAGain}`).to.equal(true)
			expect(partial.reserveLeft).to.equal(0n)

			const delta = partial.partyAGain - none.partyAGain
			const liquidatorShareBps = decimal(1n, 17) // setLiquidatorShare in Initialize.fixture
			const expectedDeltaIfFixed = (reserve * liquidatorShareBps) / decimal(1n)
			// Bug overpays ≈ R (remainingLf uses pre-reserve D). Fix: net PartyA tip ≈ R * liquidatorShare.
			expect(delta).to.equal(
				expectedDeltaIfFixed,
				`H-14: expected delta R*liquidatorShare after reserve credit; got delta=${delta} none=${none.partyAGain} partial=${partial.partyAGain} R=${reserve}`,
			)
		})
	})
}
