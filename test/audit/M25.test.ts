import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM25 } from "./M25.behavior"

describe("Audit review2 M-25", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM25()
})
