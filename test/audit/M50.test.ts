import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM50 } from "./M50.behavior"

describe("Audit review2 M-50", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM50()
})
