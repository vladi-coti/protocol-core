import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM49 } from "./M49.behavior"

describe("Audit review2 M-49", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM49()
})
