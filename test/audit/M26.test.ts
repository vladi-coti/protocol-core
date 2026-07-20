import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditM26 } from "./M26.behavior"

describe("Audit review2 M-26", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditM26()
})
