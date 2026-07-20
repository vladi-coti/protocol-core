import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

/**
 * M-49: Privacy model is numbers-only. Price/qty/locks/fees encrypted;
 * symbol/side/orderType/deadline/affiliate/whitelist stay public (matching/routing).
 * design-M-49: accept public metadata.
 */
export function shouldBehaveLikeAuditM49(): void {
	describe("quote metadata privacy scope", function () {
		it("M-49 static: Quote keeps public intent/routing fields; numerics encrypted", function () {
			const storage = fs.readFileSync(path.join(__dirname, "../../contracts/storages/QuoteStorage.sol"), "utf8")
			const quote = storage.slice(storage.indexOf("struct Quote {"), storage.indexOf("struct ViewQuote {"))
			expect(quote).to.match(/address\[\]\s+partyBsWhiteList/)
			expect(quote).to.match(/uint256\s+symbolId/)
			expect(quote).to.match(/PositionType\s+positionType/)
			expect(quote).to.match(/OrderType\s+orderType/)
			expect(quote).to.match(/uint256\s+deadline/)
			expect(quote).to.match(/address\s+affiliate/)
			expect(quote).to.match(/utUint256\s+requestedOpenPrice/)
			expect(quote).to.match(/utUint256\s+quantity/)
			expect(quote).to.match(/LockedValues\s+lockedValues/)

			const partyA = fs.readFileSync(path.join(__dirname, "../../contracts/facets/PartyA/PartyAFacet.sol"), "utf8")
			const sendQuote = partyA.slice(partyA.indexOf("function sendQuote"), partyA.indexOf("function expireQuote"))
			expect(sendQuote).to.match(/basicParams\.symbolId/)
			expect(sendQuote).to.match(/emit\s+SendQuoteForPartyA/)
			expect(sendQuote).to.match(/encryptedParams\.encryptedPrice|gtPrice/)
		})
	})
}
