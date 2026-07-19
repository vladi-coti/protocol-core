import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM02 } from "./M02.behavior"

describe("Audit review2 M-02", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM02()
})
