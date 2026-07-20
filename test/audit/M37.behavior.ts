import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-37: resolveLiquidationDispute took plaintext int256[] amounts, then setPublic + offBoard.
 * Ciphertext in storage does not undo calldata disclosure. Accept itInt256[] instead.
 */
export function shouldBehaveLikeAuditM37(): void {
	describe("liquidation dispute settlement amount privacy", function () {
		it("M-37 static: resolveLiquidationDispute takes itInt256[] not int256[]", function () {
			const iface = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/ILiquidationResolutionFacet.sol"),
				"utf8",
			)
			expect(iface).to.match(
				/function\s+resolveLiquidationDispute\s*\(\s*address\s+partyA\s*,\s*address\s*\[\s*\]\s+memory\s+partyBs\s*,\s*itInt256\s*\[\s*\]\s+calldata\s+amounts\s*,\s*bool\s+disputed\s*\)/,
			)
			expect(iface).to.not.match(/int256\s*\[\s*\]\s+(memory|calldata)\s+amounts/)

			const facet = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationResolutionFacet.sol"),
				"utf8",
			)
			const resolve = facet.slice(
				facet.indexOf("function resolveLiquidationDispute"),
				facet.lastIndexOf("}"),
			)
			expect(resolve).to.include("MpcCore.validateCiphertext(amounts[i])")
			expect(resolve).to.not.include("MpcCore.setPublic256(amounts[i])")

			const impl = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			const implResolve = impl.slice(
				impl.indexOf("function resolveLiquidationDispute"),
				impl.indexOf("function settlePartyALiquidation"),
			)
			expect(implResolve).to.match(/gtInt256\s*\[\s*\]\s+memory\s+amounts/)
			expect(implResolve).to.not.include("MpcCore.setPublic256(amounts[i])")
		})

		it("M-37: dispute resolve calldata has no plaintext settlement amount; PartyA decrypts stored actual", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))
			await runTx(
				context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), await user.getAddress()),
			)

			const partyA = await user.getAddress()
			const partyB = await hedger.getAddress()
			const amount = decimal(123n) // positive settlement override for calldata probe

			const diamond = context.diamond
			const selector = context.liquidationResolutionFacet.interface.getFunction("resolveLiquidationDispute")!.selector
			const encrypted = await context.signers.admin.encryptUint256(amount, diamond, selector)

			const tx = await context.liquidationResolutionFacet
				.connect(context.signers.admin)
				.resolveLiquidationDispute(partyA, [partyB], [encrypted as any], false)
			const receipt = await tx.wait()
			expect(receipt).to.not.be.null

			// Plaintext amount must not appear as ABI-encoded int256 in calldata (old leak).
			const data = tx.data
			const amountWord = ethers.toBeHex(amount, 32).slice(2).toLowerCase()
			expect(data.toLowerCase().includes(amountWord), "plaintext amount still in calldata").to.equal(false)

			const [state] = await context.viewFacet.getSettlementStates(partyA, [partyB])
			const stored = await (context.signers.user as any).decryptInt256(state.actualAmount)
			expect(stored).to.equal(amount)
		})
	})
}
