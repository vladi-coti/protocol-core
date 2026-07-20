import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL05 } from "./L05.behavior"

describe("Audit review2 L-05", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL05()
})
