import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH12 } from "./H12.behavior"

describe("Audit review2 H-12", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH12()
})
