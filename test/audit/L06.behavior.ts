import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitOpenRequestBuilder } from "../models/requestModels/OpenRequest"
import { decimal } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"

/**
 * L-06: PartyB-filtered views scan quotes[start..start+size) as quote IDs and
 * return a fixed-length array padded with empty ViewQuotes.
 */
export function shouldBehaveLikeAuditL06(): void {
	describe("PartyB-filtered position views", function () {
		it("L-06 static: filtered views clamp to lastId and return compact match arrays", function () {
			const view = fs.readFileSync(path.join(__dirname, "../../contracts/facets/ViewFacet/ViewFacet.sol"), "utf8")
			expect(view).to.match(/function _getPositionsFilteredByPartyB/)
			expect(view).to.match(/new ViewQuote\[\]\(count\)/)
			expect(view).to.match(/end > lastId \+ 1/)
			const fn = view.slice(
				view.indexOf("function getPositionsFilteredByPartyB"),
				view.indexOf("function getObserverPositionsFilteredByPartyB"),
			)
			expect(fn).to.match(/_getPositionsFilteredByPartyB\(/)
		})

		it("L-06: getPositionsFilteredByPartyB returns only matches (not size-padded empties)", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const q1 = await user.sendQuote()
			await user.sendQuote()
			await hedger.lockQuote(q1)
			const quantity = decimal(100n)
			await hedger.openPosition(
				q1,
				limitOpenRequestBuilder().filledAmount(quantity).openPrice(decimal(1n)).price(decimal(1n)).build(),
			)

			const partyB = await hedger.getAddress()
			const page = await context.viewFacet.getPositionsFilteredByPartyB(partyB, 0n, 100n)

			expect(page.length).to.be.greaterThan(0)
			expect(page.length).to.be.lessThan(100)
			for (const q of page) {
				expect(q.partyB).to.equal(partyB)
				expect(q.id).to.not.equal(0n)
			}
		})
	})
}
