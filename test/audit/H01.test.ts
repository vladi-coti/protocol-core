import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH01 } from "./H01.behavior"

describe("Audit review2 H-01", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH01()
})
