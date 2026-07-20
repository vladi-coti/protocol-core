import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL03 } from "./L03.behavior"

describe("Audit review2 L-03", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL03()
})
