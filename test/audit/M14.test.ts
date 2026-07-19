import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM14 } from "./M14.behavior"

describe("Audit review2 M-14", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM14()
})
