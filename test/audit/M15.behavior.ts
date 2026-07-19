import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import { toUtf8Bytes } from "ethers"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { PositionType } from "../models/Enums"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal, getBlockTimestamp } from "../utils/Common"
import { getDummyLiquidationSig } from "../utils/SignatureUtils"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-15: under H-01 path C, Muon freshness is priceValidTime only.
 * upnlValidTime remains in storage/ABI but must not gate acceptance.
 */
export function shouldBehaveLikeAuditM15(): void {
	describe("priceValidTime enforcement", function () {
		it("M-15 static: freshness uses priceValidTime only (not upnlValidTime)", function () {
			const partyA = fs.readFileSync(
				path.join(__dirname, "../../contracts/libraries/muon/LibMuonPartyA.sol"),
				"utf8",
			)
			expect(partyA).to.include("priceValidTime")
			expect(partyA).to.not.include("upnlValidTime")

			const liq = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			const liquidate = liq.slice(liq.indexOf("function liquidatePartyA"), liq.indexOf("function setSymbolsPrice"))
			expect(liquidate).to.include("priceValidTime")
			expect(liquidate).to.not.include("upnlValidTime")
			expect(liquidate).to.include("Expired price signature")

			const quotePrices = fs.readFileSync(
				path.join(__dirname, "../../contracts/libraries/muon/LibMuonLiquidation.sol"),
				"utf8",
			)
			expect(quotePrices.slice(quotePrices.indexOf("function verifyQuotePrices"))).to.include("priceValidTime")

			// No Muon lib should still require upnlValidTime for expiry.
			for (const name of [
				"LibMuon.sol",
				"LibMuonAccount.sol",
				"LibMuonPartyB.sol",
				"LibMuonForceActions.sol",
				"LibMuonSettlement.sol",
				"LibMuonFundingRate.sol",
			]) {
				const src = fs.readFileSync(path.join(__dirname, `../../contracts/libraries/muon/${name}`), "utf8")
				expect(src, name).to.not.match(/require\([^)]*upnlValidTime/)
			}
		})

		it("M-15: liquidatePartyA reverts on stale priceValidTime (upnlValidTime ignored)", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			await runTx(
				context.controlFacet
					.connect(context.signers.admin)
					.grantRole(context.signers.admin.getAddress(), ethers.keccak256(toUtf8Bytes("MUON_SETTER_ROLE"))),
			)
			// Huge legacy upnlValidTime must not rescue a stale price window.
			await runTx(context.controlFacet.connect(context.signers.admin).setMuonConfig(10_000, 1))

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const partyA = await user.getAddress()
			const open = await user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.positionType(PositionType.SHORT)
					.build(),
			)
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), partyA))
			await hedger.lockQuote(open, 0n, null)
			await hedger.openPosition(open)

			const price = decimal(8n)
			const upnl = await user.getUpnl(async () => price)
			const loss = await user.getTotalUnrealisedLoss(async () => price)
			const alloc = (await user.getBalanceInfo()).allocatedBalances
			const sig = await getDummyLiquidationSig("0x10", upnl, [1n], [price], loss, alloc)
			sig.timestamp = (await getBlockTimestamp()) - 100n
			sig.liquidationTimestamp = sig.timestamp

			await expect(
				context.liquidationFacet.connect(context.signers.liquidator).liquidatePartyA(partyA, sig),
			).to.be.revertedWith("LiquidationFacet: Expired price signature")
		})
	})
}
