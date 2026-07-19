import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM13 } from "./M13.behavior"

describe("Audit review2 M-13", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM13()
})
