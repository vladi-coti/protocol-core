import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH26 } from "./H26.behavior"

describe("Audit review2 H-26", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH26()
})
