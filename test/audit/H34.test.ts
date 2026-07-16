import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH34 } from "./H34.behavior"

describe("Audit review2 H-34", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH34()
})
