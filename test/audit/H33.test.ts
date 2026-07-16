import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH33 } from "./H33.behavior"

describe("Audit review2 H-33", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH33()
})
