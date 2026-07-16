import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH04 } from "./H04.behavior"

describe("Audit review2 H-04", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH04()
})
