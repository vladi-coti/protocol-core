import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

/**
 * L-01: NORMAL PartyA liquidation splits fee with floor(lf/2)+floor(lf/2) then deletes fee —
 * odd wei dust never paid. PartyB path floors remainingLf across positions similarly.
 */
export function shouldBehaveLikeAuditL01(): void {
	describe("liquidation fee rounding dust", function () {
		it("L-01 static: PartyA NORMAL fee split assigns remainder (no silent drop)", function () {
			const src = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			const block = src.slice(
				src.indexOf("if (accountLayout.liquidationDetails[partyA].liquidationType == LiquidationType.NORMAL)"),
				src.indexOf("delete accountLayout.liquidators[partyA]"),
			)
			expect(block).to.include("gtLf.div(MpcCore.setPublic256(uint256(2)))")
			// Second share must be fee - firstShare so odd wei is assigned.
			expect(block).to.match(/gtLf2\s*=\s*gtLf\.checkedSub\(gtLf1\)/)
			expect(block).to.not.match(/gtLf2\s*=\s*gtLf\.div\(/)
		})

		it("L-01 static: PartyB remaining LF dust goes to liquidator share", function () {
			const src = fs.readFileSync(path.join(__dirname, "../../contracts/libraries/LibLiquidation.sol"), "utf8")
			const block = src.slice(
				src.indexOf("gtLiquidatorShare = gtRemainingLf.checkedMul"),
				src.indexOf("maLayout.encryptedPartyBPositionLiquidatorsShare"),
			)
			expect(block).to.include("gtDistributedToPositions")
			expect(block).to.match(/gtLiquidatorShare\s*=\s*gtLiquidatorShare\.checkedAdd/)
		})
	})
}
