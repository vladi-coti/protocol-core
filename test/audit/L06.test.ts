import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditL06 } from "./L06.behavior"

describe("Audit review2 L-06", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditL06()
})
