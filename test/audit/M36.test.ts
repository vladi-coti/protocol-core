import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM36 } from "./M36.behavior"

describe("Audit review2 M-36", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM36()
})
