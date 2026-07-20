import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM24 } from "./M24.behavior"

describe("Audit review2 M-24", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM24()
})
