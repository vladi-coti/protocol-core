import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH32 } from "./H32.behavior"

describe("Audit review2 H-32", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH32()
})
