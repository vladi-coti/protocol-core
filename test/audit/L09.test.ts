import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL09 } from "./L09.behavior"

describe("Audit review2 L-09", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL09()
})
