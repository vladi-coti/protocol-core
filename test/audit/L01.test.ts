import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL01 } from "./L01.behavior"

describe("Audit review2 L-01", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL01()
})
