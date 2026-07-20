import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM23 } from "./M23.behavior"

describe("Audit review2 M-23", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM23()
})
