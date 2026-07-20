import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * L-03: editAccountName indexes via accountAddress but writes accounts[msg.sender][index].
 * Foreign address does not mutate victim storage — caller-only metadata footgun. Wontfix.
 */
export function shouldBehaveLikeAuditL03(): void {
	describe("editAccountName ownership", function () {
		it("L-03 static: editAccountName writes accounts[msg.sender] only (no onlyOwner)", function () {
			const src = fs.readFileSync(path.join(__dirname, "../../contracts/multiAccount/MultiAccount.sol"), "utf8")
			const fn = src.slice(src.indexOf("function editAccountName"), src.indexOf("function depositForAccount"))
			expect(fn).to.include("accounts[msg.sender][index].name")
			expect(fn).to.not.match(/onlyOwner\s*\(/)
		})

		it("L-03: foreign accountAddress renames caller's same-index account, not victim's", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const multiAccount = await ethers.getContractAt("MultiAccount", context.multiAccount)

			await runTx(multiAccount.connect(context.signers.user).addAccount("UserA0"))
			await runTx(multiAccount.connect(context.signers.user2).addAccount("UserB0"))

			const userAddr = await context.signers.user.getAddress()
			const user2Addr = await context.signers.user2.getAddress()
			const userAccounts = await multiAccount.getAccounts(userAddr, 0, 10)

			await runTx(
				multiAccount.connect(context.signers.user2).editAccountName(userAccounts[0].accountAddress, "Hijacked"),
			)

			expect((await multiAccount.getAccounts(userAddr, 0, 10))[0].name).to.equal("UserA0")
			expect((await multiAccount.getAccounts(user2Addr, 0, 10))[0].name).to.equal("Hijacked")
		})
	})
}
