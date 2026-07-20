import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM40 } from "./M40.behavior"

describe("Audit review2 M-40", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM40()
})
