import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH15 } from "./H15.behavior"

describe("Audit review2 H-15", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH15()
})
