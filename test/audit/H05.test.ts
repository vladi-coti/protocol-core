import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH05 } from "./H05.behavior"

describe("Audit review2 H-05", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH05()
})
