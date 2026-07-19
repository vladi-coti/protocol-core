import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM10 } from "./M10.behavior"

describe("Audit review2 M-10", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM10()
})
