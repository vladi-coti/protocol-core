import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH14 } from "./H14.behavior"

describe("Audit review2 H-14", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH14()
})
