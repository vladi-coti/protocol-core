import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH35 } from "./H35.behavior"

describe("Audit review2 H-35", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH35()
})
