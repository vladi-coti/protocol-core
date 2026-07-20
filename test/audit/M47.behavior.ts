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
import { decimal, decryptUint256 } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-47: LiquidationDetail plaintext deficit/fee husks stayed 0 while encrypted storage held real values.
 * View now returns ViewLiquidationDetail without husks; use dedicated encrypted getters.
 */
export function shouldBehaveLikeAuditM47(): void {
	describe("liquidation detail husk fields", function () {
		it("M-47 static: view returns ViewLiquidationDetail without plaintext husks", function () {
			const storage = fs.readFileSync(path.join(__dirname, "../../contracts/storages/AccountStorage.sol"), "utf8")
			expect(storage).to.match(/struct\s+ViewLiquidationDetail/)
			const viewDetail = storage.slice(storage.indexOf("struct ViewLiquidationDetail"), storage.indexOf("struct Price"))
			expect(viewDetail).to.not.match(/\bdeficit\b/)
			expect(viewDetail).to.not.match(/\bliquidationFee\b/)
			expect(viewDetail).to.not.match(/partyAAccumulatedUpnl/)

			const iface = fs.readFileSync(path.join(__dirname, "../../contracts/facets/ViewFacet/IViewFacet.sol"), "utf8")
			expect(iface).to.match(/getLiquidatedStateOfPartyA[\s\S]*ViewLiquidationDetail/)
			expect(iface).to.match(/liquidationDeficitOfPartyA/)
			expect(iface).to.match(/liquidationFeeOfPartyA/)
		})

		it("M-47: after setSymbolsPrice, encrypted fee/deficit nonzero while view omits husks", async function () {
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

			const partyA = await user.getAddress()
			const mark = decimal(8n)
			await user.liquidateAndSetSymbolPrices([1n], [mark])

			const state = await context.viewFacet.getLiquidatedStateOfPartyA(partyA)
			expect((state as any).deficit).to.equal(undefined)
			expect((state as any).liquidationFee).to.equal(undefined)
			expect((state as any).partyAAccumulatedUpnl).to.equal(undefined)
			expect(state.liquidationType).to.not.equal(0) // not NONE after setSymbolsPrice

			const feeCt = await context.viewFacet.liquidationFeeOfPartyA(partyA)
			const deficitCt = await context.viewFacet.liquidationDeficitOfPartyA(partyA)
			const fee = await decryptUint256(context, feeCt, context.signers.user)
			const deficit = await decryptUint256(context, deficitCt, context.signers.user)
			// At least one of fee/deficit is material after classification (NORMAL has fee; LATE/OVERDUE have deficit).
			expect(fee > 0n || deficit > 0n, "encrypted fee or deficit must be nonzero").to.equal(true)
		})
	})
}
