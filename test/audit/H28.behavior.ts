import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { decimal, decryptUint256 } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

function asCt(ct: any): { ciphertextHigh: bigint; ciphertextLow: bigint } {
	if (ct == null) throw new Error("missing ciphertext")
	if (typeof ct.ciphertextHigh === "bigint" || typeof ct.ciphertextHigh === "number") {
		return { ciphertextHigh: BigInt(ct.ciphertextHigh), ciphertextLow: BigInt(ct.ciphertextLow) }
	}
	// ethers Result tuple fallback
	return { ciphertextHigh: BigInt(ct[0]), ciphertextLow: BigInt(ct[1]) }
}

function isZeroCt(ct: any): boolean {
	const n = asCt(ct)
	return n.ciphertextHigh === 0n && n.ciphertextLow === 0n
}

function isFlatCt(ct: any): boolean {
	if (ct == null || typeof ct !== "object") return false
	if ("userCiphertext" in ct || "ciphertext" in ct) return false
	try {
		asCt(ct)
		return true
	} catch {
		return false
	}
}

/**
 * H-28: public quote views must return ViewQuote (ctUint256 only), not storage Quote (utUint256).
 */
export function shouldBehaveLikeAuditH28(): void {
	describe("quote view system-ciphertext redaction", function () {
		it("H-28 static: quote views return ViewQuote via _toViewQuote / _toObserverViewQuote", function () {
			const src = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/ViewFacet/ViewFacet.sol"),
				"utf8",
			)
			const iface = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/ViewFacet/IViewFacet.sol"),
				"utf8",
			)
			expect(iface).to.match(/function\s+getQuote\([^)]*\)\s+external\s+view\s+returns\s*\(\s*ViewQuote\s+memory\s*\)/)
			expect(iface).to.match(/function\s+getPartyAOpenPositions\([^)]*\)\s+external\s+view\s+returns\s*\(\s*ViewQuote\s*\[\s*\]\s+memory\s*\)/)
			expect(iface).to.not.match(/function\s+getQuote\([^)]*\)\s+external\s+view\s+returns\s*\(\s*Quote\s+memory\s*\)/)

			const getQuote = src.slice(src.indexOf("function getQuote("), src.indexOf("function getObserverQuote("))
			expect(getQuote).to.match(/_toViewQuote\s*\(/)
			expect(getQuote).to.not.match(/_redactSystemCiphertext/)

			expect(src).to.match(/function\s+_toViewQuote\s*\(/)
			expect(src).to.match(/function\s+_toObserverViewQuote\s*\(/)
			expect(src).to.not.match(/function\s+_redactSystemCiphertext/)

			const storage = fs.readFileSync(
				path.join(__dirname, "../../contracts/storages/QuoteStorage.sol"),
				"utf8",
			)
			const viewQuote = storage.slice(storage.indexOf("struct ViewQuote"), storage.indexOf("struct EncryptedQuoteValues"))
			expect(viewQuote).to.match(/ctUint256\s+openedPrice/)
			expect(viewQuote).to.match(/UserLockedValues\s+lockedValues/)
			expect(viewQuote).to.not.match(/utUint256\s+openedPrice/)
		})

		it("H-28: getQuote returns flat user ciphertext; no nested system ciphertext; PartyA decrypts", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))
			await runTx(context.accountFacet.connect(context.signers.hedger).allocateForPartyB(decimal(500n), await user.getAddress()))

			const open = await user.sendQuote()
			await hedger.lockQuote(open)
			await hedger.openPosition(open)

			const quoteId = open.quoteId
			const partyA = await user.getAddress()

			const strangerQuote = await context.viewFacet.connect(context.signers.user2).getQuote(quoteId)
			// ViewQuote: openedPrice is ctUint256, not utUint256 { ciphertext, userCiphertext }
			expect(isFlatCt(strangerQuote.openedPrice), "openedPrice must be flat ctUint256").to.equal(true)
			expect(isFlatCt(strangerQuote.quantity), "quantity must be flat ctUint256").to.equal(true)
			expect(isFlatCt(strangerQuote.lockedValues.lf), "lockedValues.lf must be flat ctUint256").to.equal(true)
			expect(isZeroCt(strangerQuote.openedPrice)).to.equal(false)
			expect(isZeroCt(strangerQuote.quantity)).to.equal(false)
			expect(isZeroCt(strangerQuote.lockedValues.lf)).to.equal(false)

			const strangerPositions = await context.viewFacet
				.connect(context.signers.user2)
				.getPartyAOpenPositions(partyA, 0, 10)
			expect(strangerPositions.length).to.be.greaterThan(0)
			expect(isFlatCt(strangerPositions[0].openedPrice)).to.equal(true)

			const observerQuote = await context.viewFacet.connect(context.signers.user2).getObserverQuote(quoteId)
			expect(isFlatCt(observerQuote.openedPrice), "observer openedPrice must be flat ctUint256").to.equal(true)

			const opened = await decryptUint256(context, asCt(strangerQuote.openedPrice), user.getWallet())
			const qty = await decryptUint256(context, asCt(strangerQuote.quantity), user.getWallet())
			expect(opened).to.not.equal(0n)
			expect(qty).to.not.equal(0n)

			const strangerOpened = await decryptUint256(context, asCt(strangerQuote.openedPrice), context.signers.user2 as any)
			expect(strangerOpened).to.not.equal(opened)
		})
	})
}
