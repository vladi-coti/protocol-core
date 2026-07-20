import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM16 } from "./M16.behavior"

describe("Audit review2 M-16", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM16()
})
