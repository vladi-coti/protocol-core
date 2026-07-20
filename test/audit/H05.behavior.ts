import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-05: report claimed LiquidationDetail.upnl / totalUnrealizedLoss are plaintext int256.
 * Current code stores them as utInt256 via LibEncryption.offBoardToUser (H-01 path C leftover).
 */
export function shouldBehaveLikeAuditH05(): void {
	describe("PartyA liquidation risk snapshot privacy", function () {
		it("H-05 static: LiquidationDetail risk fields are utInt256 + offBoardToUser", function () {
			const storage = fs.readFileSync(
				path.join(__dirname, "../../contracts/storages/AccountStorage.sol"),
				"utf8",
			)
			const detail = storage.slice(storage.indexOf("struct LiquidationDetail"), storage.indexOf("struct Price"))
			expect(detail).to.match(/utInt256\s+upnl/)
			expect(detail).to.match(/utInt256\s+totalUnrealizedLoss/)
			expect(detail).to.not.match(/int256\s+upnl/)
			expect(detail).to.not.match(/int256\s+totalUnrealizedLoss/)

			const impl = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			const liquidate = impl.slice(impl.indexOf("function liquidatePartyA"), impl.indexOf("function setSymbolsPrice"))
			expect(liquidate).to.include("LibEncryption.offBoardToUser(gtUpnl")
			expect(liquidate).to.include("LibEncryption.offBoardToUser(gtTotalUnrealizedLoss")
		})

		it("H-05: getLiquidatedStateOfPartyA UPNL/loss are user-decryptable ciphertext, not plaintext ints", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const open = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), await user.getAddress()))
			await hedger.lockQuote(open, 0n, null)
			await hedger.openPosition(open)

			const mark = decimal(8n)
			await user.liquidateAndSetSymbolPrices([1n], [mark])

			const state = await user.getLiquidatedStateOfPartyA()
			expect(state.upnl.userCiphertext).to.not.equal(undefined)
			expect(state.totalUnrealizedLoss.userCiphertext).to.not.equal(undefined)

			const upnl = await (context.signers.user as any).decryptInt256(state.upnl.userCiphertext)
			const loss = await (context.signers.user as any).decryptInt256(state.totalUnrealizedLoss.userCiphertext)
			expect(upnl).to.not.equal(0n)
			expect(loss).to.not.equal(0n)

			// Stranger must not recover PartyA's plaintext risk from the view ciphertext.
			const strangerUpnl = await (context.signers.user2 as any).decryptInt256(state.upnl.userCiphertext)
			expect(strangerUpnl).to.not.equal(upnl)

			// M-47: husk fields removed from view return; encrypted getters hold real values.
			expect((state as any).deficit).to.equal(undefined)
			expect((state as any).liquidationFee).to.equal(undefined)
		})
	})
}
