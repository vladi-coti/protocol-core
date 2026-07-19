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

const REALIZED_PNL_IN = 4
const REALIZED_PNL_OUT = 5

const sharedEventsInterface = new ethers.Interface([
	"event BalanceChangePartyA(address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
	"event BalanceChangePartyB(address indexed partyB, address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
	"event ObserverBalanceChangePartyA(address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
	"event ObserverBalanceChangePartyB(address indexed partyB, address indexed partyA, tuple(uint256 ciphertextHigh, uint256 ciphertextLow) amount, uint8 _type)",
])

function parseSharedEvents(receipt: any) {
	return receipt.logs
		.map((log: any) => {
			try {
				return sharedEventsInterface.parseLog(log)
			} catch {
				return null
			}
		})
		.filter(Boolean)
}

/**
 * M-14: ObserverBalanceChange* only emitted on allocate/deallocate.
 * PnL / fee / liquidation balance mutations update observer storage but skip observer events.
 */
export function shouldBehaveLikeAuditM14(): void {
	describe("observer balance-change event coverage", function () {
		it("M-14 static: ObserverBalanceChange emits only live in AccountFacet", function () {
			const contractsRoot = path.join(__dirname, "../../contracts")
			const emitFiles: string[] = []
			const walk = (dir: string) => {
				for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
					const full = path.join(dir, entry.name)
					if (entry.isDirectory()) walk(full)
					else if (entry.name.endsWith(".sol")) {
						const src = fs.readFileSync(full, "utf8")
						if (/emit\s+SharedEvents\.ObserverBalanceChange/.test(src)) emitFiles.push(path.relative(contractsRoot, full))
					}
				}
			}
			walk(contractsRoot)
			expect(emitFiles).to.deep.equal(["facets/Account/AccountFacet.sol"])
		})

		it("M-14: fillClose updates observer allocated storage but emits no ObserverBalanceChange PnL", async function () {
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
			const observerBefore = await context.viewFacet.observerAllocatedBalanceOfPartyA(partyA)
			const observerBeforeVal = await decryptUint256(context, observerBefore, context.signers.liquidator)

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

			const parsed = parseSharedEvents(receipt)
			const userPnl = parsed.filter(
				(e: any) =>
					(e.name === "BalanceChangePartyA" || e.name === "BalanceChangePartyB") &&
					(Number(e.args._type) === REALIZED_PNL_IN || Number(e.args._type) === REALIZED_PNL_OUT),
			)
			const observerPnl = parsed.filter(
				(e: any) =>
					(e.name === "ObserverBalanceChangePartyA" || e.name === "ObserverBalanceChangePartyB") &&
					(Number(e.args._type) === REALIZED_PNL_IN || Number(e.args._type) === REALIZED_PNL_OUT),
			)
			const anyObserver = parsed.filter(
				(e: any) => e.name === "ObserverBalanceChangePartyA" || e.name === "ObserverBalanceChangePartyB",
			)

			expect(userPnl.length, "user PnL BalanceChange events expected").to.be.greaterThan(0)
			expect(observerPnl.length, "ObserverBalanceChange must not cover PnL").to.equal(0)
			expect(anyObserver.length, "fillClose must not emit any ObserverBalanceChange").to.equal(0)

			const observerAfter = await context.viewFacet.observerAllocatedBalanceOfPartyA(partyA)
			const observerAfterVal = await decryptUint256(context, observerAfter, context.signers.liquidator)
			expect(observerAfterVal, "observer storage must still track PnL via store helpers").to.not.equal(observerBeforeVal)
		})
	})
}
