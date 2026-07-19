import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH11 } from "./H11.behavior"

describe("Audit review2 H-11", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH11()
})
