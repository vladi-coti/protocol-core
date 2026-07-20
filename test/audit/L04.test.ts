import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL04 } from "./L04.behavior"

describe("Audit review2 L-04", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL04()
})
