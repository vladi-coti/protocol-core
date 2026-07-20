import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH28 } from "./H28.behavior"

describe("Audit review2 H-28", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH28()
})
