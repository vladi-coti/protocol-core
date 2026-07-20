import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL08 } from "./L08.behavior"

describe("Audit review2 L-08", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL08()
})
