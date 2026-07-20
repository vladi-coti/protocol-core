import "../utils/revertedWith"
import { expect } from "chai"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

import { initializeFixture } from "../Initialize.fixture"
import { Hedger } from "../models/Hedger"
import { RunContext } from "../models/RunContext"
import { User } from "../models/User"
import { limitCloseRequestBuilder } from "../models/requestModels/CloseRequest"
import { limitFillCloseRequestBuilder } from "../models/requestModels/FillCloseRequest"
import { decimal, decryptUint256, getBlockTimestamp, getQuoteQuantity } from "../utils/Common"
import { loadFixtureCompatible } from "../utils/testHelpers"
import { runTx } from "../utils/TxUtils"

const ALLOCATE = 0
const REALIZED_PNL_IN = 4
const REALIZED_PNL_OUT = 5

const sharedEventsInterface = new ethers.Interface([
	"event BalanceChangePartyA(address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
	"event BalanceChangePartyB(address indexed partyB, address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
])

function parseBalanceChangePartyA(receipt: any) {
	return receipt.logs
		.map((log: any) => {
			try {
				return sharedEventsInterface.parseLog(log)
			} catch {
				return null
			}
		})
		.filter((e: any) => e && e.name === "BalanceChangePartyA")
}

/**
 * M-25: BalanceChangePartyA.amount mixes snapshot (ALLOCATE/DEALLOCATE) and delta (PnL/fees).
 * Naive indexer that always adds `amount` drifts on allocate.
 */
export function shouldBehaveLikeAuditM25(): void {
	describe("balance-change amount semantics", function () {
		it("M-25 static: ALLOCATE reads post-balance ciphertext; settlement emits delta amount", function () {
			const account = fs.readFileSync(path.join(__dirname, "../../contracts/facets/Account/AccountFacet.sol"), "utf8")
			const allocate = account.slice(account.indexOf("function allocate("), account.indexOf("function depositAndAllocate"))
			expect(allocate).to.match(/allocatedBalances\[msg\.sender\]\.userCiphertext/)
			expect(allocate).to.match(/BalanceChangeType\.ALLOCATE/)

			const settlement = fs.readFileSync(path.join(__dirname, "../../contracts/libraries/LibSettlement.sol"), "utf8")
			expect(settlement).to.match(/offBoardToUser\(gtAmount/)
			expect(settlement).to.match(/BalanceChangeType\.REALIZED_PNL_IN/)
			expect(settlement).to.match(/BalanceChangeType\.REALIZED_PNL_OUT/)

			// Same type name, but amount is full allocated balance (snapshot-before-wipe), not PnL delta.
			const liq = fs.readFileSync(path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"), "utf8")
			expect(liq).to.match(
				/ctAllocatedBalance\s*=\s*MpcCore\.offBoardToUser\(gtAllocatedBalance[\s\S]*?REALIZED_PNL_OUT/,
			)
		})

		it("M-25: ALLOCATE BalanceChange amount is post-balance snapshot, not allocate delta", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)
			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), 0n)

			const first = decimal(500n)
			const second = decimal(300n)

			await runTx(context.accountFacet.connect(context.signers.user).allocate(first))
			const tx2 = await context.accountFacet.connect(context.signers.user).allocate(second)
			const receipt = await tx2.wait()
			expect(receipt).to.not.be.null

			const allocateEvents = parseBalanceChangePartyA(receipt).filter((e: any) => Number(e.args._type) === ALLOCATE)
			expect(allocateEvents.length).to.equal(1)

			const eventAmount = await decryptUint256(context, allocateEvents[0].args.amount, context.signers.user)
			expect(eventAmount, "naive delta indexer would expect second allocate only").to.not.equal(second)
			expect(eventAmount, "ALLOCATE amount is post allocated snapshot").to.equal(first + second)

			const stored = await decryptUint256(
				context,
				await context.viewFacet.allocatedBalanceOfPartyA(await user.getAddress()),
				context.signers.user,
			)
			expect(eventAmount).to.equal(stored)
		})

		it("M-25: REALIZED_PNL BalanceChange amount is PnL delta, not post allocated snapshot", async function () {
			const context: RunContext = await loadFixtureCompatible(initializeFixture)

			const user = new User(context, context.signers.user)
			await user.setup()
			await user.setBalances(decimal(2000n), decimal(1000n), decimal(500n))

			const liquidator = new User(context, context.signers.liquidator)
			await liquidator.setup()
			await runTx(context.accountFacet.connect(context.signers.liquidator).allocate(0))
			await runTx(
				context.controlFacet.connect(context.signers.admin).setTrustedObserverAddress(context.signers.liquidator.address),
			)

			const hedger = new Hedger(context, context.signers.hedger)
			await hedger.setup()
			await hedger.setBalances(decimal(2000n), decimal(1000n))

			const quote = await user.sendQuote()
			await hedger.lockQuote(quote)
			await hedger.openPosition(quote)

			const partyA = await user.getAddress()
			const allocBefore = await decryptUint256(
				context,
				await context.viewFacet.allocatedBalanceOfPartyA(partyA),
				context.signers.user,
			)

			const qty = await getQuoteQuantity(context, quote.quoteId)
			await user.requestToClosePosition(
				quote.quoteId,
				limitCloseRequestBuilder()
					.quantityToClose(qty)
					.closePrice(decimal(2n))
					.deadline((await getBlockTimestamp()) + 1000n)
					.build(),
			)

			const fillReq = limitFillCloseRequestBuilder().filledAmount(qty).closedPrice(decimal(2n)).build()
			const { encryptedParams, upnlSig } = await hedger.buildFillCloseRequestCalldataArgs(fillReq)
			const partyAPositions = await context.viewFacet.getPartyAOpenPositions(partyA, 0, 100)
			const partyBPositions = await context.viewFacet.getPartyBOpenPositions(await hedger.getAddress(), partyA, 0, 100)
			;(upnlSig as any).partyAQuoteIds = partyAPositions.map((q: any) => BigInt(q.id))
			;(upnlSig as any).partyAPrices = partyAPositions.map(() => BigInt(fillReq.price))
			;(upnlSig as any).partyBQuoteIds = partyBPositions.map((q: any) => BigInt(q.id))
			;(upnlSig as any).partyBPrices = partyBPositions.map(() => BigInt(fillReq.price))

			const tx = await context.partyBCloseActionsFacet
				.connect(context.signers.hedger)
				.fillCloseRequest(quote.quoteId, encryptedParams, upnlSig)
			const receipt = await tx.wait()
			expect(receipt).to.not.be.null

			const pnlEvents = parseBalanceChangePartyA(receipt).filter(
				(e: any) => Number(e.args._type) === REALIZED_PNL_IN || Number(e.args._type) === REALIZED_PNL_OUT,
			)
			expect(pnlEvents.length, "expected PartyA PnL BalanceChange").to.be.greaterThan(0)

			const allocAfter = await decryptUint256(
				context,
				await context.viewFacet.allocatedBalanceOfPartyA(partyA),
				context.signers.user,
			)
			const balanceDelta = allocAfter > allocBefore ? allocAfter - allocBefore : allocBefore - allocAfter

			let pnlFromEvents = 0n
			for (const e of pnlEvents) {
				const amt = await decryptUint256(context, e.args.amount, context.signers.user)
				pnlFromEvents += amt
				expect(amt, "PnL event must not be full post-balance snapshot").to.not.equal(allocAfter)
			}
			expect(pnlFromEvents, "PnL event amounts track allocated balance delta").to.equal(balanceDelta)
		})
	})
}
