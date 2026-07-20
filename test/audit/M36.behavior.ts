import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

/**
 * M-36 claimed: deferred reimbursement does checkedSub(currentAllocated, available)
 * when available (alloc - locks + upnl) can exceed currentAllocated → underflow.
 *
 * After H-16, insolvency + reimbursement share one snapshot-based available:
 * require(available < 0) then if (available > 0) reimburse — second branch dead.
 * Underflow path unreachable on current branch.
 */
export function shouldBehaveLikeAuditM36(): void {
	describe("deferred liquidation reimbursement underflow", function () {
		it("M-36 static: reimbursement uses same available that must be < 0 (H-16)", function () {
			const src = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/DeferredLiquidationFacetImpl.sol"),
				"utf8",
			)
			const fn = src.slice(
				src.indexOf("function deferredLiquidatePartyA"),
				src.indexOf("function deferredSetSymbolsPrice"),
			)

			expect(fn).to.include("liquidationSig.liquidationAllocatedBalance")
			expect(fn).to.include('require(MpcCore.decrypt(gtLiquidationAvailableBalance.lt(gtZero))')
			expect(fn).to.include("gtInt256 gtAvailableBalance = gtLiquidationAvailableBalance")
			expect(fn).to.include("gtAvailableBalance.gt(gtZero)")

			const insolvencyAt = fn.indexOf("gtLiquidationAvailableBalance.lt(gtZero)")
			const reimburseAt = fn.indexOf("gtAvailableBalance.gt(gtZero)")
			expect(insolvencyAt).to.be.greaterThan(-1)
			expect(reimburseAt).to.be.greaterThan(insolvencyAt)

			// Must not recompute availability from *current* allocated for the reimburse gate.
			const afterRequire = fn.slice(insolvencyAt)
			expect(afterRequire).to.not.match(
				/partyAAvailableBalanceForLiquidation\(\s*gtUpnl\s*,\s*partyA\s*\)/,
			)
		})
	})
}
