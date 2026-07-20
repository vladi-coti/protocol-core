import "../utils/revertedWith"
import { expect } from "chai"
import * as fs from "fs"
import * as path from "path"

/**
 * M-16: LiquidationType (NORMAL/LATE/OVERDUE) is public storage derived from
 * private deficit vs LF/LF+CVA. Exact deficit stays encrypted; severity bucket
 * is intentional lifecycle disclosure (design-M-16: keep public).
 */
export function shouldBehaveLikeAuditM16(): void {
	describe("liquidation type disclosure", function () {
		it("M-16 static: LiquidationDetail.liquidationType stays public enum (intentional)", function () {
			const storage = fs.readFileSync(path.join(__dirname, "../../contracts/storages/AccountStorage.sol"), "utf8")
			expect(storage).to.match(/enum\s+LiquidationType/)
			expect(storage).to.match(/struct\s+LiquidationDetail[\s\S]*LiquidationType\s+liquidationType/)

			const view = fs.readFileSync(path.join(__dirname, "../../contracts/facets/ViewFacet/IViewFacet.sol"), "utf8")
			expect(view).to.match(/getLiquidatedStateOfPartyA[\s\S]*ViewLiquidationDetail/)

			const facet = fs.readFileSync(
				path.join(__dirname, "../../contracts/facets/liquidation/LiquidationFacetImpl.sol"),
				"utf8",
			)
			expect(facet).to.match(/liquidationType\s*=\s*LiquidationType\.NORMAL/)
			expect(facet).to.match(/liquidationType\s*=\s*LiquidationType\.LATE/)
			expect(facet).to.match(/liquidationType\s*=\s*LiquidationType\.OVERDUE/)
			expect(facet).to.match(/MpcCore\.decrypt\(gtNormal\)/)
		})
	})
}
