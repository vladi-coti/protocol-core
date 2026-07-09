import "../utils/revertedWith"
import { setupAccounts } from "../utils/accounts"
import { shouldBehaveLikeAuditH02 } from "./H02.behavior"

describe("Audit review2 H-02", function () {
	before(async function () {
		await setupAccounts()
	})

	shouldBehaveLikeAuditH02()
})
