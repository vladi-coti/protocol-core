import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH16 } from "./H16.behavior"

describe("Audit review2 H-16", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH16()
})
