import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * M-11: whenNotInternalTransferPaused omitted globalPaused, so pauseGlobal alone
 * left internalTransfer open while other fund paths were frozen.
 */
export function shouldBehaveLikeAuditM11(): void {
	describe("global pause blocks internalTransfer", function () {
		it("M-11 static: whenNotInternalTransferPaused checks globalPaused", function () {
			const src = fs.readFileSync(path.join(__dirname, "../../contracts/utils/Pausable.sol"), "utf8")
			const mod = src.slice(
				src.indexOf("modifier whenNotInternalTransferPaused"),
				src.indexOf("}", src.indexOf("modifier whenNotInternalTransferPaused")) + 1,
			)
			expect(mod).to.include("globalPaused")
			expect(mod).to.include("Pausable: Global paused")
		})

		it("M-11: pauseGlobal alone reverts internalTransfer", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(1000n), decimal(500n), decimal(0n))

			const user2 = new User(context, context.signers.user2)
			await user2.setup()

			await runTx(context.controlFacet.connect(context.signers.admin).pauseGlobal())

			await expect(
				context.accountFacet.connect(context.signers.user).internalTransfer(await user2.getAddress(), decimal(1n)),
			).to.be.revertedWith("Pausable: Global paused")
		})
	})
}
