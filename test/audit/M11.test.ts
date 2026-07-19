import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM11 } from "./M11.behavior"

describe("Audit review2 M-11", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM11()
})
