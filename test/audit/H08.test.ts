import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH08 } from "./H08.behavior"

describe("Audit review2 H-08", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH08()
})
