import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM47 } from "./M47.behavior"

describe("Audit review2 M-47", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM47()
})
