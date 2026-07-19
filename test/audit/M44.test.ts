import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM44 } from "./M44.behavior"

describe("Audit review2 M-44", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM44()
})
