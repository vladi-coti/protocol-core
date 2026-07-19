import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM15 } from "./M15.behavior"

describe("Audit review2 M-15", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM15()
})
