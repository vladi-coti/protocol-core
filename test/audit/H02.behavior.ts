import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"

function solidityFiles(dir: string): string[] {
	return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
		const fullPath = path.join(dir, entry.name)
		if (entry.isDirectory()) return solidityFiles(fullPath)
		return entry.isFile() && entry.name.endsWith(".sol") ? [fullPath] : []
	})
}

function isAllowedLockedValueStructOp(line: string): boolean {
	return (
		line.includes(".onBoard().sub(") ||
		line.includes("gtQuoteLockedValues.sub(") ||
		line.includes(".add(garbledLockedValues)") ||
		line.includes(".add(gtNewLockedValues)")
	)
}

/**
 * H-02: signed encrypted accounting uses MpcCore.checkedAdd/Sub(gtInt256).
 */
export function shouldBehaveLikeAuditH02(): void {
	describe("LibAccount regression", function () {
		let context: RunContext
		let user: User

		beforeEach(async function () {
			context = await loadFixtureCompatible(initializeFixture)
			user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1500n), decimal(1200n))
		})

		it("H-02: sendQuote balance check still rejects unaffordable quotes", async function () {
			await expect(
				user.sendQuote(
					limitQuoteRequestBuilder()
						.partyBWhiteList([context.signers.hedger.address])
						.affiliate(context.multiAccount)
						.price(decimal(16n))
						.quantity(decimal(200n))
						.cva(decimal(2000n))
						.partyAmm(decimal(2000n))
						.lf(decimal(2000n))
						.build(),
				),
			).to.be.revertedWith("PartyAFacet: insufficient available balance")
		})

		it("H-02: signed MPC arithmetic must use checked helpers", function () {
			const contractsRoot = path.join(__dirname, "../../contracts")
			const offenders = solidityFiles(contractsRoot).flatMap((file) => {
				const relative = path.relative(contractsRoot, file)
				return fs
					.readFileSync(file, "utf8")
					.split("\n")
					.flatMap((line, index) => {
						const usesRawAddSub = /\.(add|sub)\(/.test(line)
						const usesCheckedHelper = /\.(checkedAdd|checkedSub)\(/.test(line)
						if (!usesRawAddSub || usesCheckedHelper || isAllowedLockedValueStructOp(line)) return []
						return [`${relative}:${index + 1}: ${line.trim()}`]
					})
			})

			expect(offenders).to.deep.equal([])
		})
	})
}
