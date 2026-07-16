import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

/**
 * H-08: allocate / internalTransfer decrypt the encrypted allocated-balance
 * limit before checking the caller's plaintext free balance. An underfunded
 * caller can still learn whether amount would breach the private limit via
 * which require reverts first.
 *
 * Fix: public balance check before encrypted limit decrypt.
 */
export function shouldBehaveLikeAuditH08(): void {
	describe("account allocate/internalTransfer revert-order oracle", function () {
		async function setup() {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const user = new User(context, context.signers.user)
			await user.setup()
			// Small free balance for underfunded probes (approve+mint+deposit via helper).
			await user.setBalances(50n, 50n, 0n)
			return { context, user }
		}

		it("H-08: underfunded allocate must not reveal limit via early encrypted revert", async function () {
			const { context } = await setup()
			const account = context.accountFacet.connect(context.signers.user)

			await runTx(context.controlFacet.connect(context.signers.admin).setBalanceLimitPerUser(100n))

			// free=50, amount=200 → exceeds limit AND underfunded.
			// Bug: "Allocated balance limit reached" first (private oracle).
			// Fix: "Insufficient balance" first (public check).
			await expect(account.allocate(200n)).to.be.revertedWith("AccountFacet: Insufficient balance")
		})

		it("H-08: underfunded internalTransfer must not reveal recipient limit early", async function () {
			const { context } = await setup()
			const sender = context.signers.user
			const recipient = context.signers.user2
			const account = context.accountFacet.connect(sender)

			await runTx(context.controlFacet.connect(context.signers.admin).setBalanceLimitPerUser(100n))

			await expect(account.internalTransfer(await recipient.getAddress(), 200n)).to.be.revertedWith(
				"AccountFacet: Insufficient balance",
			)
		})

		it("H-08: allocate/internalTransfer must check free balance before limit decrypt", function () {
			const srcPath = path.join(__dirname, "../../contracts/facets/Account/AccountFacetImpl.sol")
			const src = fs.readFileSync(srcPath, "utf8")

			for (const fnName of ["function allocate(", "function internalTransfer("]) {
				const start = src.indexOf(fnName)
				expect(start, fnName).to.be.gte(0)
				const next = src.indexOf("\n\tfunction ", start + 1)
				const body = src.slice(start, next === -1 ? src.length : next)
				const publicAt = body.indexOf('require(accountLayout.balances[msg.sender] >= amount')
				const limitAt = body.indexOf("Allocated balance limit reached")
				expect(publicAt, `${fnName} missing public balance require`).to.be.gte(0)
				expect(limitAt, `${fnName} missing limit require`).to.be.gte(0)
				expect(publicAt).to.be.lessThan(
					limitAt,
					`H-08: ${fnName} public balance check must precede encrypted limit decrypt`,
				)
			}
		})
	})
}
