import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH38 } from "./H38.behavior"

describe("Audit review2 H-38", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH38()
})
