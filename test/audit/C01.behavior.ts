import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitQuoteRequestBuilder } from "../models/requestModels/QuoteRequest"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"

const TWO_255 = 1n << 255n
const TWO_254 = 1n << 254n

function solidityFiles(dir: string): string[] {
	return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
		const fullPath = path.join(dir, entry.name)
		if (entry.isDirectory()) return solidityFiles(fullPath)
		return entry.isFile() && entry.name.endsWith(".sol") ? [fullPath] : []
	})
}

/**
 * C-01 validation: unsigned encrypted values cast via toSigned() without proving value < 2^255.
 * Concrete exploit path from review1/report3#5 via PartyAFacetImpl.sol:96.
 */
export function shouldBehaveLikeAuditC01(): void {
	let context: RunContext
	let user: User

	beforeEach(async function () {
		context = await loadFixtureCompatible(initializeFixture)
		user = new User(context, context.signers.user)
		await user.setup()
		await user.setBalances(decimal(2000n), decimal(1500n), decimal(1200n))
	})

	function highBitQuoteRequest() {
		const partyAmm = decimal(100n)
		const lf = TWO_255 / 100n + 1n
		const cva = TWO_255 - lf - partyAmm

		expect(cva + partyAmm + lf).to.equal(TWO_255)

		return limitQuoteRequestBuilder()
			.partyBWhiteList([context.signers.hedger.address])
			.affiliate(context.multiAccount)
			.price(decimal(1n))
			.quantity(decimal(1n))
			.cva(cva)
			.partyAmm(partyAmm)
			.lf(lf)
			.partyBmm(decimal(1n))
			.build()
	}

	it("C-01: rejects sendQuote when totalRequired is honestly unaffordable (control)", async function () {
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

	it("C-01: high-bit totalRequired must not bypass sendQuote balance check (tx)", async function () {
		await expect(user.sendQuote(highBitQuoteRequest())).to.be.reverted
	})

	it("C-01: report3-style 2^254+2^254 locked values must not open quote with low allocation", async function () {
		await expect(
			user.sendQuote(
				limitQuoteRequestBuilder()
					.partyBWhiteList([context.signers.hedger.address])
					.affiliate(context.multiAccount)
					.price(decimal(1n))
					.quantity(decimal(1n))
					.cva(TWO_254)
					.partyAmm(TWO_254)
					.lf(decimal(100n))
					.partyBmm(decimal(1n))
					.build(),
			),
		).to.be.reverted
	})

	it("C-01: contracts must not use raw gtUint256.toSigned casts", function () {
		const contractsRoot = path.join(__dirname, "../../contracts")
		const offenders = solidityFiles(contractsRoot).flatMap((file) => {
			const relative = path.relative(contractsRoot, file)
			return fs
				.readFileSync(file, "utf8")
				.split("\n")
				.flatMap((line, index) => (line.includes(".toSigned()") ? [`${relative}:${index + 1}: ${line.trim()}`] : []))
		})

		expect(offenders).to.deep.equal([])
	})
}
