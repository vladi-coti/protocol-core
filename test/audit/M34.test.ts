import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM34 } from "./M34.behavior"

describe("Audit review2 M-34", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM34()
})
