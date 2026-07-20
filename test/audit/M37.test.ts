import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM37 } from "./M37.behavior"

describe("Audit review2 M-37", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM37()
})
